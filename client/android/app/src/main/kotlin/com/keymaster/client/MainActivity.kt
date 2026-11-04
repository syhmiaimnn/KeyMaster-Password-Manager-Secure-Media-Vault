package com.keymaster.client

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterFragmentActivity() {

    private val keyAlias = "keymaster_biometric_key"
    private val keystoreName = "AndroidKeyStore"
    private val transformation = "AES/GCM/NoPadding"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // -----------------------------------------------------------------
        // Channel 1: the "secure window" flag.
        // With the flag on, screenshots, screen recordings and the recent-apps
        // preview show a black screen instead of the app.
        // -----------------------------------------------------------------
        MethodChannel(messenger, "keymaster/privacy")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val on = call.argument<Boolean>("on") ?: true
                        runOnUiThread {
                            if (on) {
                                window.setFlags(
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                    WindowManager.LayoutParams.FLAG_SECURE
                                )
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // -----------------------------------------------------------------
        // Channel 2: fingerprint unlock with a key kept in the Android Keystore.
        // The key is created with "user authentication required", so Android
        // only lets it be used right after a successful fingerprint scan. The
        // key itself can never be read out of the Keystore.
        // -----------------------------------------------------------------
        MethodChannel(messenger, "keymaster/biometric")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(biometricStatus())
                    "enroll" -> enroll(
                        call.argument<String>("secret"),
                        call.argument<String>("title") ?: "Fingerprint",
                        call.argument<String>("subtitle") ?: "",
                        call.argument<String>("negative") ?: "Cancel",
                        result
                    )
                    "unlock" -> unlock(
                        call.argument<String>("blob"),
                        call.argument<String>("title") ?: "Fingerprint",
                        call.argument<String>("subtitle") ?: "",
                        call.argument<String>("negative") ?: "Cancel",
                        result
                    )
                    "deleteKey" -> {
                        deleteKey()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------------------------------------------------------------
    // Fingerprint helpers
    // ---------------------------------------------------------------------

    /** "ready", "not_enrolled", "weak_only" or "unavailable". */
    private fun biometricStatus(): String {
        // Android Keystore keys with fingerprint protection need Android 6.0.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "unavailable"
        val manager = BiometricManager.from(this)
        val strong = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        if (strong == BiometricManager.BIOMETRIC_SUCCESS) return "ready"
        if (strong == BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED) return "not_enrolled"
        val weak = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        if (weak == BiometricManager.BIOMETRIC_SUCCESS) return "weak_only"
        return "unavailable"
    }

    private fun loadKeyStore(): KeyStore {
        val store = KeyStore.getInstance(keystoreName)
        store.load(null)
        return store
    }

    private fun deleteKey() {
        try {
            val store = loadKeyStore()
            if (store.containsAlias(keyAlias)) store.deleteEntry(keyAlias)
        } catch (e: Exception) {
            // Nothing to delete, or the Keystore is not reachable.
        }
    }

    private fun createKey() {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, keystoreName)
        val builder = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 0 = a fingerprint scan is needed for every single use of the key.
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Adding a new fingerprint to the phone makes this key unusable.
            builder.setInvalidatedByBiometricEnrollment(true)
        }
        generator.init(builder.build())
        generator.generateKey()
    }

    private fun loadKey(): SecretKey? {
        return loadKeyStore().getKey(keyAlias, null) as? SecretKey
    }

    /** Shows the fingerprint prompt. [cipher] is only usable after a scan. */
    private fun showPrompt(
        cipher: Cipher,
        title: String,
        subtitle: String,
        negative: String,
        onSuccess: (Cipher) -> Unit,
        onError: (String, String) -> Unit
    ) {
        // Runs the prompt's callbacks on the main thread.
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val executor = java.util.concurrent.Executor { command -> handler.post(command) }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                val unlocked = result.cryptoObject?.cipher
                if (unlocked == null) {
                    onError("failed", "No cipher returned")
                    return
                }
                try {
                    onSuccess(unlocked)
                } catch (e: Exception) {
                    onError("failed", e.message ?: "Cipher error")
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val code = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "cancelled"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
                    BiometricPrompt.ERROR_NO_BIOMETRICS,
                    BiometricPrompt.ERROR_HW_NOT_PRESENT,
                    BiometricPrompt.ERROR_HW_UNAVAILABLE -> "unavailable"
                    else -> "failed"
                }
                onError(code, errString.toString())
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText(negative)
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        BiometricPrompt(this, executor, callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    /**
     * Creates a new Keystore key, asks for a fingerprint and uses the key to
     * encrypt [secretText] (the vault key, as base64). Replies with
     * "<iv>.<ciphertext>", both base64.
     */
    private fun enroll(
        secretText: String?,
        title: String,
        subtitle: String,
        negative: String,
        result: MethodChannel.Result
    ) {
        if (secretText == null) {
            result.error("failed", "No secret given", null)
            return
        }
        var replied = false
        fun reply(code: String?, value: String?) {
            if (replied) return
            replied = true
            if (code == null) {
                result.success(value)
            } else {
                result.error(code, value, null)
            }
        }
        try {
            deleteKey()
            createKey()
            val key = loadKey() ?: throw IllegalStateException("The key was not created")
            val cipher = Cipher.getInstance(transformation)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            showPrompt(
                cipher, title, subtitle, negative,
                { unlocked ->
                    val secret = Base64.decode(secretText, Base64.NO_WRAP)
                    val encrypted = unlocked.doFinal(secret)
                    java.util.Arrays.fill(secret, 0.toByte())
                    val iv = Base64.encodeToString(unlocked.iv, Base64.NO_WRAP)
                    val body = Base64.encodeToString(encrypted, Base64.NO_WRAP)
                    reply(null, "$iv.$body")
                },
                { code, message ->
                    // The key is useless if nothing was encrypted with it.
                    deleteKey()
                    reply(code, message)
                }
            )
        } catch (e: Exception) {
            deleteKey()
            reply("failed", e.message ?: "Could not set up the key")
        }
    }

    /**
     * Asks for a fingerprint and uses the Keystore key to decrypt [blob]
     * ("<iv>.<ciphertext>"). Replies with the secret as base64.
     * Replies with the code "invalidated" when the key is gone or was
     * invalidated, which happens when a new fingerprint is added to the phone.
     */
    private fun unlock(
        blob: String?,
        title: String,
        subtitle: String,
        negative: String,
        result: MethodChannel.Result
    ) {
        val parts = blob?.split(".")
        if (parts == null || parts.size != 2) {
            result.error("failed", "Bad data", null)
            return
        }
        var replied = false
        fun reply(code: String?, value: String?) {
            if (replied) return
            replied = true
            if (code == null) {
                result.success(value)
            } else {
                result.error(code, value, null)
            }
        }
        try {
            val key = loadKey()
            if (key == null) {
                reply("invalidated", "The key no longer exists")
                return
            }
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            val body = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipher = Cipher.getInstance(transformation)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            showPrompt(
                cipher, title, subtitle, negative,
                { unlocked ->
                    val secret = unlocked.doFinal(body)
                    val text = Base64.encodeToString(secret, Base64.NO_WRAP)
                    java.util.Arrays.fill(secret, 0.toByte())
                    reply(null, text)
                },
                { code, message -> reply(code, message) }
            )
        } catch (e: KeyPermanentlyInvalidatedException) {
            deleteKey()
            reply("invalidated", "A new fingerprint was added to the phone")
        } catch (e: Exception) {
            reply("failed", e.message ?: "Could not unlock")
        }
    }
}
