#ifndef FLUTTER_PLUGIN_EZKEY_KEYSTORE_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_EZKEY_KEYSTORE_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// Registers the org.ezkey.keystore channel (EzKey device keys in the TPM through CNG).
FLUTTER_PLUGIN_EXPORT void EzkeyKeystorePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_EZKEY_KEYSTORE_PLUGIN_C_API_H_
