package org.ezkey.keystore

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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
 * Generation requests StrongBox first and falls back to the TEE. The private key never leaves the
 * Keystore: the channel only carries aliases, the string to sign, signatures and public keys.
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
        return mapOf("publicKey" to encode(pair.public.encoded), "tier" to if (strongBox) "strong" else "standard")
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
    }
}
