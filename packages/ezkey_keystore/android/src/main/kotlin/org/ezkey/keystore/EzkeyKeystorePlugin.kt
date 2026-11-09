package org.ezkey.keystore

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Non-exportable EC P-256 signing keys in the Android Keystore (EzKey device keys).
 *
 * Generation requests StrongBox first and falls back to the TEE. The tier it reports is then read
 * back from the generated key ([keyTier]), never assumed from the request (#108): best effort,
 * verified, reported as it is, `none` included. The private key never leaves the Keystore: the
 * channel only carries aliases, the string to sign, signatures, public keys and tiers.
 * Keystore calls run on a background thread (StrongBox operations can take hundreds of ms).
 * Error messages never contain the signed payload.
 */
class EzkeyKeystorePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "generateKeyPair" -> runInBackground(result) { generateKeyPair(call.requireString("alias")) }
            "sign" -> runInBackground(result) { sign(call.requireString("alias"), call.requireString("payload")) }
            "publicKey" -> runInBackground(result) { publicKey(call.requireString("alias")) }
            "keyTier" -> runInBackground(result) { keyTier(call.requireString("alias")) }
            "deleteKeyPair" -> runInBackground(result) {
                keyStore().deleteEntry(call.requireString("alias"))
                null
            }
            "aliases" -> runInBackground(result) {
                val prefix = call.argument<String>("prefix") ?: ""
                keyStore().aliases().toList().filter { it.startsWith(prefix) }
            }
            else -> result.notImplemented()
        }
    }

    private fun generateKeyPair(alias: String): Map<String, Any> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        ) {
            try {
                return generateKeyPair(alias, strongBox = true)
            } catch (_: StrongBoxUnavailableException) {
                // Fall back to the TEE below.
            }
        }
        return generateKeyPair(alias, strongBox = false)
    }

    private fun generateKeyPair(alias: String, strongBox: Boolean): Map<String, Any> {
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            spec.setIsStrongBoxBacked(true)
        }
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE)
        generator.initialize(spec.build())
        val pair = generator.generateKeyPair()
        // What was requested proves nothing: the tier is what Android says about the key it made.
        return mapOf("publicKey" to encode(pair.public.encoded), "tier" to (keyTier(alias) ?: TIER_NONE))
    }

    /**
     * The tier Android reports for the key of [alias], or null when the alias has no key:
     * - `strong`: StrongBox, confirmed by `KeyInfo.getSecurityLevel()` (API 31+);
     * - `standard`: secure hardware, the TEE or a secure level Android does not name. Before API 31,
     *   `isInsideSecureHardware` cannot tell StrongBox from the TEE, so a StrongBox key is reported
     *   `standard` there: the app underclaims rather than claim what it cannot prove;
     * - `none`: software, or a level Android cannot tell.
     */
    private fun keyTier(alias: String): String? {
        val key = keyStore().getKey(alias, null) as? PrivateKey ?: return null
        val info = KeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE).getKeySpec(key, KeyInfo::class.java)
        val tier: String
        val evidence: String
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            tier = when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> TIER_STRONG
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT, KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE -> TIER_STANDARD
                else -> TIER_NONE
            }
            evidence = "securityLevel=${info.securityLevel}"
        } else {
            @Suppress("DEPRECATION")
            val inside = info.isInsideSecureHardware
            tier = if (inside) TIER_STANDARD else TIER_NONE
            evidence = "isInsideSecureHardware=$inside"
        }
        // Observable on any device with logcat: what Android said, and the tier the app drew from it.
        Log.i(TAG, "Storage tier read back: $evidence (API ${Build.VERSION.SDK_INT}) -> $tier")
        return tier
    }

    /** Signs the UTF-8 bytes of [payload]; returns ASN.1 DER, standard Base64 (may be high-S). */
    private fun sign(alias: String, payload: String): String {
        val key = keyStore().getKey(alias, null) as? PrivateKey ?: throw KeyNotFoundException(alias)
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(key)
        signature.update(payload.toByteArray(Charsets.UTF_8))
        return encode(signature.sign())
    }

    /** SPKI DER, standard Base64, or null when the alias does not exist. */
    private fun publicKey(alias: String): String? =
        keyStore().getCertificate(alias)?.publicKey?.encoded?.let(::encode)

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)

    private fun runInBackground(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: KeyNotFoundException) {
                mainHandler.post { result.error("key_not_found", e.message, null) }
            } catch (e: IllegalArgumentException) {
                mainHandler.post { result.error("invalid_arguments", e.message, null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("keystore_error", e.javaClass.simpleName, null) }
            }
        }
    }

    private fun MethodCall.requireString(name: String): String =
        argument<String>(name) ?: throw IllegalArgumentException("Missing argument: $name")

    private class KeyNotFoundException(alias: String) : Exception("No key for alias $alias")

    private companion object {
        const val CHANNEL = "org.ezkey.keystore"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val TAG = "EzkeyKeystore"
        const val TIER_STRONG = "strong"
        const val TIER_STANDARD = "standard"
        const val TIER_NONE = "none"
    }
}
