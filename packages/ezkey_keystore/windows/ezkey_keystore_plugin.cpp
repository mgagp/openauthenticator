// Non-exportable EC P-256 signing keys for EzKey device keys on Windows, through CNG (#134).
//
// Same channel contract as the Android plugin (docs/adr/0004-ezkey-multi-platform-posture.md D2):
// generateKeyPair, sign, publicKey, keyTier, deleteKeyPair, aliases; SPKI DER and ASN.1 DER signatures
// in standard Base64; error codes key_not_found, invalid_arguments, keystore_error.
//
// Keys are created in the TPM through the Microsoft Platform Crypto Provider. When that fails (no TPM, or
// a TPM CNG cannot use), the key is created in the Microsoft Software Key Storage Provider instead: best
// effort, reported as tier `none`. The tier is read back from the key (#108): `standard` only when the
// key's own PCP_PLATFORM_TYPE property says it is in a TPM 2.0. No `strong` on Windows.
//
// The calls run one at a time, in order, on a worker thread (a TPM key takes about 0.5 s to create, a
// signature 60 to 90 ms), and each result is posted back to the platform thread through a message-only
// window: the same model as the Android plugin's single-thread executor.
// Error messages carry a CNG status code only, never key material or payloads.
//
// Debug builds only: EZKEY_KEYSTORE_FORCE_SOFTWARE=1 in the environment skips the TPM, so the software
// fallback can be tested on a PC that has one. Release and profile builds ignore it.

#include "include/ezkey_keystore/ezkey_keystore_plugin_c_api.h"

// clang-format off
#include <windows.h>
#include <bcrypt.h>
#include <ncrypt.h>
#include <wincrypt.h>
// clang-format on

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

// The plugin DLL's own module handle, for its window class.
extern "C" IMAGE_DOS_HEADER __ImageBase;

#ifndef NCRYPT_PCP_PLATFORM_TYPE_PROPERTY
#define NCRYPT_PCP_PLATFORM_TYPE_PROPERTY L"PCP_PLATFORM_TYPE"
#endif

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kChannel[] = "org.ezkey.keystore";
constexpr char kTierStandard[] = "standard";
constexpr char kTierNone[] = "none";

// A CNG failure, carried as its status code only.
struct CngError {
  SECURITY_STATUS status;
};

// No key under the requested alias.
struct KeyNotFound {
  std::string alias;
};

// A required argument is missing.
struct InvalidArguments {
  std::string message;
};

// Owns one NCrypt handle (provider or key).
class NcryptHandle {
 public:
  NcryptHandle() = default;
  ~NcryptHandle() {
    if (handle_ != 0) {
      NCryptFreeObject(handle_);
    }
  }
  NcryptHandle(const NcryptHandle&) = delete;
  NcryptHandle& operator=(const NcryptHandle&) = delete;
  NcryptHandle(NcryptHandle&& other) noexcept : handle_(other.handle_) { other.handle_ = 0; }
  NcryptHandle& operator=(NcryptHandle&& other) noexcept {
    std::swap(handle_, other.handle_);
    return *this;
  }

  NCRYPT_HANDLE* out() { return &handle_; }
  NCRYPT_HANDLE get() const { return handle_; }
  NCRYPT_HANDLE release() {
    NCRYPT_HANDLE handle = handle_;
    handle_ = 0;
    return handle;
  }

 private:
  NCRYPT_HANDLE handle_ = 0;
};

// A key opened in one provider. The provider handle is kept open as long as the key handle.
struct OpenedKey {
  NcryptHandle provider;
  NcryptHandle key;
  bool hardware = false;
};

// The providers, in the order keys are created and looked up.
struct Provider {
  LPCWSTR name;
  bool hardware;
};
constexpr Provider kHardwareProvider = {MS_PLATFORM_CRYPTO_PROVIDER, true};
constexpr Provider kSoftwareProvider = {MS_KEY_STORAGE_PROVIDER, false};

#ifdef _DEBUG
// Whether a debug build was asked to skip the TPM (tests of the software fallback).
bool SoftwareForced() {
  static const bool forced = [] {
    char value[4] = {};
    return GetEnvironmentVariableA("EZKEY_KEYSTORE_FORCE_SOFTWARE", value, sizeof(value)) == 1 && value[0] == '1';
  }();
  return forced;
}
#else
constexpr bool SoftwareForced() { return false; }
#endif

// The providers in use, in the order keys are created and looked up: the TPM first.
const std::vector<Provider>& Providers() {
  static const std::vector<Provider> providers = SoftwareForced() ? std::vector<Provider>{kSoftwareProvider} : std::vector<Provider>{kHardwareProvider, kSoftwareProvider};
  return providers;
}

void Check(SECURITY_STATUS status) {
  if (status != ERROR_SUCCESS) {
    throw CngError{status};
  }
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) {
    throw InvalidArguments{"Invalid UTF-8"};
  }
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), wide.data(), size);
  return wide;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
  std::string text(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), text.data(), size, nullptr, nullptr);
  return text;
}

std::string Base64(const std::vector<BYTE>& data) {
  DWORD length = 0;
  DWORD flags = CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF;
  if (!CryptBinaryToStringA(data.data(), static_cast<DWORD>(data.size()), flags, nullptr, &length)) {
    throw CngError{static_cast<SECURITY_STATUS>(HRESULT_FROM_WIN32(GetLastError()))};
  }
  std::string text(length, '\0');
  if (!CryptBinaryToStringA(data.data(), static_cast<DWORD>(data.size()), flags, text.data(), &length)) {
    throw CngError{static_cast<SECURITY_STATUS>(HRESULT_FROM_WIN32(GetLastError()))};
  }
  text.resize(length);
  return text;
}

// Opens the key of [alias] in [provider], or nothing when the provider is unusable or has no such key.
std::optional<OpenedKey> TryOpenKey(const Provider& provider, const std::wstring& alias) {
  OpenedKey opened;
  if (NCryptOpenStorageProvider(opened.provider.out(), provider.name, 0) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  SECURITY_STATUS status = NCryptOpenKey(opened.provider.get(), opened.key.out(), alias.c_str(), 0, NCRYPT_SILENT_FLAG);
  // A missing key: the software provider says NTE_BAD_KEYSET; the PCP may answer with another code.
  if (status == NTE_BAD_KEYSET || status == NTE_NO_KEY || status == NTE_NOT_FOUND) {
    if (status != NTE_BAD_KEYSET) {
      char buffer[96];
      std::snprintf(buffer, sizeof(buffer), "EzkeyKeystore: missing key reported as 0x%08X\n", static_cast<unsigned int>(status));
      OutputDebugStringA(buffer);
    }
    return std::nullopt;
  }
  Check(status);
  opened.hardware = provider.hardware;
  return opened;
}

// Opens the key of [alias], looking in the TPM first.
std::optional<OpenedKey> FindKey(const std::wstring& alias) {
  for (const Provider& provider : Providers()) {
    std::optional<OpenedKey> opened = TryOpenKey(provider, alias);
    if (opened) {
      return opened;
    }
  }
  return std::nullopt;
}

// The tier of an opened key, read back from the key itself.
std::string TierOf(const OpenedKey& opened) {
  std::string tier = kTierNone;
  std::string evidence = "software provider";
  if (opened.hardware) {
    wchar_t platform[256] = {};
    DWORD size = 0;
    SECURITY_STATUS status = NCryptGetProperty(opened.key.get(), NCRYPT_PCP_PLATFORM_TYPE_PROPERTY, reinterpret_cast<PBYTE>(platform), sizeof(platform) - sizeof(wchar_t), &size, 0);
    if (status == ERROR_SUCCESS) {
      std::wstring value(platform);
      evidence = "PCP_PLATFORM_TYPE=" + WideToUtf8(value);
      if (value.rfind(L"TPM-Version:2.0", 0) == 0) {
        tier = kTierStandard;
      }
    } else {
      char buffer[64];
      std::snprintf(buffer, sizeof(buffer), "PCP_PLATFORM_TYPE unreadable (0x%08X)", static_cast<unsigned int>(status));
      evidence = buffer;
    }
  }
  // Observable with a debugger or DebugView: what Windows said, and the tier drawn from it.
  OutputDebugStringA(("EzkeyKeystore: storage tier read back: " + evidence + " -> " + tier + "\n").c_str());
  return tier;
}

// The SPKI DER of a P-256 public key: the fixed algorithm header, then the uncompressed point.
std::vector<BYTE> SpkiOf(NCRYPT_KEY_HANDLE key) {
  DWORD size = 0;
  Check(NCryptExportKey(key, 0, BCRYPT_ECCPUBLIC_BLOB, nullptr, nullptr, 0, &size, 0));
  std::vector<BYTE> blob(size);
  Check(NCryptExportKey(key, 0, BCRYPT_ECCPUBLIC_BLOB, nullptr, blob.data(), size, &size, 0));
  const BCRYPT_ECCKEY_BLOB* header = reinterpret_cast<const BCRYPT_ECCKEY_BLOB*>(blob.data());
  if (size < sizeof(BCRYPT_ECCKEY_BLOB) + 64 || header->dwMagic != BCRYPT_ECDSA_PUBLIC_P256_MAGIC || header->cbKey != 32) {
    throw CngError{NTE_BAD_DATA};
  }
  static const BYTE kPrefix[] = {0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06,
                                 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04};
  std::vector<BYTE> spki(kPrefix, kPrefix + sizeof(kPrefix));
  const BYTE* point = blob.data() + sizeof(BCRYPT_ECCKEY_BLOB);
  spki.insert(spki.end(), point, point + 64);
  return spki;
}

// Appends one ASN.1 DER INTEGER for a big-endian unsigned value.
void AppendDerInteger(std::vector<BYTE>& out, const BYTE* value, size_t length) {
  size_t start = 0;
  while (start < length - 1 && value[start] == 0) {
    start++;
  }
  bool pad = (value[start] & 0x80) != 0;
  out.push_back(0x02);
  out.push_back(static_cast<BYTE>(length - start + (pad ? 1 : 0)));
  if (pad) {
    out.push_back(0x00);
  }
  out.insert(out.end(), value + start, value + length);
}

// Converts CNG's IEEE P1363 signature (r || s, 32 bytes each) to ASN.1 DER.
std::vector<BYTE> P1363ToDer(const std::vector<BYTE>& signature) {
  if (signature.size() != 64) {
    throw CngError{NTE_BAD_SIGNATURE};
  }
  std::vector<BYTE> body;
  AppendDerInteger(body, signature.data(), 32);
  AppendDerInteger(body, signature.data() + 32, 32);
  std::vector<BYTE> der = {0x30, static_cast<BYTE>(body.size())};
  der.insert(der.end(), body.begin(), body.end());
  return der;
}

std::vector<BYTE> Sha256(const std::string& data) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  NTSTATUS status = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
  if (status < 0) {
    throw CngError{status};
  }
  std::vector<BYTE> digest(32);
  BCRYPT_HASH_HANDLE hash = nullptr;
  status = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0);
  if (status >= 0) {
    status = BCryptHashData(hash, reinterpret_cast<PUCHAR>(const_cast<char*>(data.data())), static_cast<ULONG>(data.size()), 0);
  }
  if (status >= 0) {
    status = BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0);
  }
  if (hash != nullptr) {
    BCryptDestroyHash(hash);
  }
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (status < 0) {
    throw CngError{status};
  }
  return digest;
}

// Deletes the key of [alias] from every provider (no-op when there is none).
void DeleteKeyPair(const std::wstring& alias) {
  for (const Provider& provider : Providers()) {
    std::optional<OpenedKey> opened = TryOpenKey(provider, alias);
    if (!opened) {
      continue;
    }
    NCRYPT_KEY_HANDLE key = opened->key.release();
    // No NCRYPT_SILENT_FLAG here: the PCP refuses it on delete (NTE_BAD_FLAGS), although it is documented.
    SECURITY_STATUS status = NCryptDeleteKey(key, 0);
    if (status != ERROR_SUCCESS) {
      NCryptFreeObject(key);
      throw CngError{status};
    }
  }
}

// Creates a persisted, sign-only P-256 key under [alias] in [provider].
SECURITY_STATUS CreateKey(const Provider& provider, const std::wstring& alias, OpenedKey& out) {
  OpenedKey created;
  SECURITY_STATUS status = NCryptOpenStorageProvider(created.provider.out(), provider.name, 0);
  if (status != ERROR_SUCCESS) {
    return status;
  }
  status = NCryptCreatePersistedKey(created.provider.get(), created.key.out(), BCRYPT_ECDSA_P256_ALGORITHM, alias.c_str(), 0, NCRYPT_OVERWRITE_KEY_FLAG);
  if (status != ERROR_SUCCESS) {
    return status;
  }
  DWORD usage = NCRYPT_ALLOW_SIGNING_FLAG;
  status = NCryptSetProperty(created.key.get(), NCRYPT_KEY_USAGE_PROPERTY, reinterpret_cast<PBYTE>(&usage), sizeof(usage), 0);
  if (status != ERROR_SUCCESS) {
    return status;
  }
  // No export policy is set: CNG keys are not exportable by default, and the PCP cannot export a private key.
  status = NCryptFinalizeKey(created.key.get(), NCRYPT_SILENT_FLAG);
  if (status != ERROR_SUCCESS) {
    return status;
  }
  created.hardware = provider.hardware;
  out = std::move(created);
  return ERROR_SUCCESS;
}

EncodableMap GenerateKeyPair(const std::wstring& alias) {
  // Like the Android Keystore, a new key replaces any key under the same alias.
  DeleteKeyPair(alias);
  OpenedKey created;
  SECURITY_STATUS status = NTE_PROV_TYPE_NOT_DEF;
  for (const Provider& provider : Providers()) {
    status = CreateKey(provider, alias, created);
    if (status == ERROR_SUCCESS) {
      break;
    }
    if (provider.hardware) {
      char buffer[96];
      std::snprintf(buffer, sizeof(buffer), "EzkeyKeystore: TPM key creation failed (0x%08X), software fallback\n", static_cast<unsigned int>(status));
      OutputDebugStringA(buffer);
    }
  }
  Check(status);
  return EncodableMap{
      {EncodableValue("publicKey"), EncodableValue(Base64(SpkiOf(created.key.get())))},
      {EncodableValue("tier"), EncodableValue(TierOf(created))},
  };
}

std::string Sign(const std::wstring& alias, const std::string& payload) {
  std::optional<OpenedKey> opened = FindKey(alias);
  if (!opened) {
    throw KeyNotFound{WideToUtf8(alias)};
  }
  std::vector<BYTE> digest = Sha256(payload);
  DWORD size = 0;
  Check(NCryptSignHash(opened->key.get(), nullptr, digest.data(), static_cast<DWORD>(digest.size()), nullptr, 0, &size, NCRYPT_SILENT_FLAG));
  std::vector<BYTE> signature(size);
  Check(NCryptSignHash(opened->key.get(), nullptr, digest.data(), static_cast<DWORD>(digest.size()), signature.data(), size, &size, NCRYPT_SILENT_FLAG));
  signature.resize(size);
  return Base64(P1363ToDer(signature));
}

EncodableList Aliases(const std::string& prefix) {
  EncodableList result;
  std::vector<std::string> seen;
  for (const Provider& provider : Providers()) {
    NcryptHandle handle;
    if (NCryptOpenStorageProvider(handle.out(), provider.name, 0) != ERROR_SUCCESS) {
      continue;
    }
    PVOID state = nullptr;
    while (true) {
      NCryptKeyName* name = nullptr;
      SECURITY_STATUS status = NCryptEnumKeys(handle.get(), nullptr, &name, &state, NCRYPT_SILENT_FLAG);
      if (status == NTE_NO_MORE_ITEMS) {
        break;
      }
      if (status != ERROR_SUCCESS) {
        if (state != nullptr) {
          NCryptFreeBuffer(state);
        }
        throw CngError{status};
      }
      std::string alias = WideToUtf8(name->pszName);
      NCryptFreeBuffer(name);
      if (alias.rfind(prefix, 0) == 0 && std::find(seen.begin(), seen.end(), alias) == seen.end()) {
        seen.push_back(alias);
        result.push_back(EncodableValue(alias));
      }
    }
    if (state != nullptr) {
      NCryptFreeBuffer(state);
    }
  }
  return result;
}

const std::string* StringArgument(const EncodableMap* arguments, const char* name) {
  if (arguments == nullptr) {
    return nullptr;
  }
  auto found = arguments->find(EncodableValue(name));
  return found == arguments->end() ? nullptr : std::get_if<std::string>(&found->second);
}

std::wstring RequireAlias(const EncodableMap* arguments) {
  const std::string* alias = StringArgument(arguments, "alias");
  if (alias == nullptr) {
    throw InvalidArguments{"Missing argument: alias"};
  }
  return Utf8ToWide(*alias);
}

// What a call produced: computed on the worker thread, delivered on the platform thread.
struct Outcome {
  enum class Kind { kSuccess, kError, kNotImplemented };
  Kind kind = Kind::kSuccess;
  EncodableValue value;
  std::string code;
  std::string message;

  static Outcome Success(EncodableValue value = EncodableValue()) { return Outcome{Kind::kSuccess, std::move(value), {}, {}}; }
  static Outcome Error(std::string code, std::string message) { return Outcome{Kind::kError, EncodableValue(), std::move(code), std::move(message)}; }
  static Outcome NotImplemented() { return Outcome{Kind::kNotImplemented, EncodableValue(), {}, {}}; }
};

// Runs one channel method. Called on the worker thread; touches no Flutter object.
Outcome Run(const std::string& method, const EncodableValue& argument_value) {
  const EncodableMap* arguments = std::get_if<EncodableMap>(&argument_value);
  try {
    if (method == "generateKeyPair") {
      return Outcome::Success(EncodableValue(GenerateKeyPair(RequireAlias(arguments))));
    }
    if (method == "sign") {
      const std::string* payload = StringArgument(arguments, "payload");
      if (payload == nullptr) {
        throw InvalidArguments{"Missing argument: payload"};
      }
      return Outcome::Success(EncodableValue(Sign(RequireAlias(arguments), *payload)));
    }
    if (method == "publicKey") {
      std::optional<OpenedKey> opened = FindKey(RequireAlias(arguments));
      return opened ? Outcome::Success(EncodableValue(Base64(SpkiOf(opened->key.get())))) : Outcome::Success();
    }
    if (method == "keyTier") {
      std::optional<OpenedKey> opened = FindKey(RequireAlias(arguments));
      return opened ? Outcome::Success(EncodableValue(TierOf(*opened))) : Outcome::Success();
    }
    if (method == "deleteKeyPair") {
      DeleteKeyPair(RequireAlias(arguments));
      return Outcome::Success();
    }
    if (method == "aliases") {
      const std::string* prefix = StringArgument(arguments, "prefix");
      return Outcome::Success(EncodableValue(Aliases(prefix == nullptr ? std::string() : *prefix)));
    }
    return Outcome::NotImplemented();
  } catch (const KeyNotFound& error) {
    return Outcome::Error("key_not_found", "No key for alias " + error.alias);
  } catch (const InvalidArguments& error) {
    return Outcome::Error("invalid_arguments", error.message);
  } catch (const CngError& error) {
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "CNG 0x%08X", static_cast<unsigned int>(error.status));
    return Outcome::Error("keystore_error", buffer);
  } catch (const std::exception&) {
    return Outcome::Error("keystore_error", "exception");
  }
}

// A finished call, posted to the platform thread to be answered there.
struct Completion {
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
  Outcome outcome;

  void Deliver() {
    switch (outcome.kind) {
      case Outcome::Kind::kSuccess:
        result->Success(outcome.value);
        break;
      case Outcome::Kind::kError:
        result->Error(outcome.code, outcome.message);
        break;
      case Outcome::Kind::kNotImplemented:
        result->NotImplemented();
        break;
    }
  }
};

// Runs jobs one at a time, in the order they were queued, on its own thread.
class SerialWorker {
 public:
  SerialWorker() : thread_([this] { Loop(); }) {}
  ~SerialWorker() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
    }
    ready_.notify_one();
    thread_.join();
  }
  SerialWorker(const SerialWorker&) = delete;
  SerialWorker& operator=(const SerialWorker&) = delete;

  void Post(std::function<void()> job) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      jobs_.push_back(std::move(job));
    }
    ready_.notify_one();
  }

 private:
  // Runs until stopped: the job in progress finishes, the queued ones are dropped.
  void Loop() {
    while (true) {
      std::function<void()> job;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [this] { return stopping_ || !jobs_.empty(); });
        if (stopping_) {
          return;
        }
        job = std::move(jobs_.front());
        jobs_.pop_front();
      }
      job();
    }
  }

  std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<std::function<void()>> jobs_;
  bool stopping_ = false;
  std::thread thread_;  // Last: it starts once the members it uses exist.
};

constexpr UINT kCompletionMessage = WM_APP + 1;
constexpr wchar_t kWindowClass[] = L"EzkeyKeystoreMessageWindow";

class EzkeyKeystorePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(registrar->messenger(), kChannel, &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<EzkeyKeystorePlugin>();
    EzkeyKeystorePlugin* handler = plugin.get();
    channel->SetMethodCallHandler([handler](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) { handler->HandleMethodCall(call, std::move(result)); });
    plugin->channel_ = std::move(channel);
    registrar->AddPlugin(std::move(plugin));
  }

  // Created and destroyed on the platform thread, whose message loop serves the window.
  EzkeyKeystorePlugin() {
    HINSTANCE instance = reinterpret_cast<HINSTANCE>(&__ImageBase);
    WNDCLASSW window_class = {};
    window_class.lpfnWndProc = WindowProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kWindowClass;
    RegisterClassW(&window_class);  // Fails harmlessly when an earlier engine in this process registered it.
    window_ = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
    worker_ = std::make_unique<SerialWorker>();
  }

  ~EzkeyKeystorePlugin() override {
    channel_.reset();
    worker_.reset();  // Waits for the job in progress, which may still post its completion.
    if (window_ != nullptr) {
      MSG message;
      while (PeekMessageW(&message, window_, kCompletionMessage, kCompletionMessage, PM_REMOVE)) {
        delete reinterpret_cast<Completion*>(message.lParam);  // The engine is going away: nobody to answer.
      }
      DestroyWindow(window_);
    }
  }

  EzkeyKeystorePlugin(const EzkeyKeystorePlugin&) = delete;
  EzkeyKeystorePlugin& operator=(const EzkeyKeystorePlugin&) = delete;

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == kCompletionMessage) {
      std::unique_ptr<Completion> completion(reinterpret_cast<Completion*>(lparam));
      completion->Deliver();
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  void HandleMethodCall(const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (window_ == nullptr) {
      result->Error("keystore_error", "no message window");
      return;
    }
    // The call does not outlive this handler, so the job gets its own copies. std::function needs a copyable
    // job, so the pending result travels in a shared pointer until the job posts it.
    auto pending = std::make_shared<Completion>();
    pending->result = std::move(result);
    std::string method = call.method_name();
    EncodableValue arguments = call.arguments() == nullptr ? EncodableValue() : *call.arguments();
    HWND window = window_;
    worker_->Post([window, method = std::move(method), arguments = std::move(arguments), pending] {
      Completion* posted = new Completion{std::move(pending->result), Run(method, arguments)};
      if (!PostMessageW(window, kCompletionMessage, 0, reinterpret_cast<LPARAM>(posted))) {
        delete posted;
      }
    });
  }

  HWND window_ = nullptr;
  std::unique_ptr<SerialWorker> worker_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
};

}  // namespace

void EzkeyKeystorePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  EzkeyKeystorePlugin::RegisterWithRegistrar(flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
