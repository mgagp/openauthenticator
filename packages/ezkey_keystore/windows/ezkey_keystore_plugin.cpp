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
// Proof of concept: the calls run on the platform thread (TPM operations take tens to hundreds of ms).
// Error messages carry a CNG status code only, never key material or payloads.

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
#include <cstdio>
#include <memory>
#include <optional>
#include <string>
#include <vector>

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
constexpr Provider kProviders[] = {{MS_PLATFORM_CRYPTO_PROVIDER, true}, {MS_KEY_STORAGE_PROVIDER, false}};

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
  for (const Provider& provider : kProviders) {
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
  for (const Provider& provider : kProviders) {
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
  SECURITY_STATUS status = CreateKey(kProviders[0], alias, created);
  if (status != ERROR_SUCCESS) {
    char buffer[96];
    std::snprintf(buffer, sizeof(buffer), "EzkeyKeystore: TPM key creation failed (0x%08X), software fallback\n", static_cast<unsigned int>(status));
    OutputDebugStringA(buffer);
    Check(CreateKey(kProviders[1], alias, created));
  }
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
  for (const Provider& provider : kProviders) {
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

class EzkeyKeystorePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(registrar->messenger(), kChannel, &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<EzkeyKeystorePlugin>();
    channel->SetMethodCallHandler([](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) { HandleMethodCall(call, std::move(result)); });
    plugin->channel_ = std::move(channel);
    registrar->AddPlugin(std::move(plugin));
  }

 private:
  static void HandleMethodCall(const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const EncodableMap* arguments = std::get_if<EncodableMap>(call.arguments());
    const std::string& method = call.method_name();
    try {
      if (method == "generateKeyPair") {
        result->Success(EncodableValue(GenerateKeyPair(RequireAlias(arguments))));
      } else if (method == "sign") {
        const std::string* payload = StringArgument(arguments, "payload");
        if (payload == nullptr) {
          throw InvalidArguments{"Missing argument: payload"};
        }
        result->Success(EncodableValue(Sign(RequireAlias(arguments), *payload)));
      } else if (method == "publicKey") {
        std::optional<OpenedKey> opened = FindKey(RequireAlias(arguments));
        opened ? result->Success(EncodableValue(Base64(SpkiOf(opened->key.get())))) : result->Success();
      } else if (method == "keyTier") {
        std::optional<OpenedKey> opened = FindKey(RequireAlias(arguments));
        opened ? result->Success(EncodableValue(TierOf(*opened))) : result->Success();
      } else if (method == "deleteKeyPair") {
        DeleteKeyPair(RequireAlias(arguments));
        result->Success();
      } else if (method == "aliases") {
        const std::string* prefix = StringArgument(arguments, "prefix");
        result->Success(EncodableValue(Aliases(prefix == nullptr ? std::string() : *prefix)));
      } else {
        result->NotImplemented();
      }
    } catch (const KeyNotFound& error) {
      result->Error("key_not_found", "No key for alias " + error.alias);
    } catch (const InvalidArguments& error) {
      result->Error("invalid_arguments", error.message);
    } catch (const CngError& error) {
      char buffer[32];
      std::snprintf(buffer, sizeof(buffer), "CNG 0x%08X", static_cast<unsigned int>(error.status));
      result->Error("keystore_error", buffer);
    } catch (const std::exception&) {
      result->Error("keystore_error", "exception");
    }
  }

  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
};

}  // namespace

void EzkeyKeystorePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  EzkeyKeystorePlugin::RegisterWithRegistrar(flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
