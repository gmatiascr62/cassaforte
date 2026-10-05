package io.github.gmatiascr62.cassaforte

import android.annotation.TargetApi
import android.app.Activity
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Protege la clave de la bóveda con una llave AES-256-GCM del Android
 * Keystore (hardware seguro, no exportable) que exige autenticarse con
 * huella fuerte o con el bloqueo de pantalla en cada uso. Android la
 * destruye si se añaden huellas o se quita el bloqueo de pantalla.
 *
 * Requiere Android 11 (API 30): es la primera versión que permite usar el
 * patrón/PIN del teléfono junto con una llave criptográfica.
 */
class BiometricChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = OnceResult(result)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            when (call.method) {
                "status" -> reply.success("unsupported")
                "deleteKey" -> reply.success(null)
                else -> reply.error("unsupported", "Requiere Android 11 o superior", null)
            }
            return
        }
        handle(call, reply)
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun handle(call: MethodCall, reply: OnceResult) {
        try {
            when (call.method) {
                "status" -> reply.success(status())
                "wrap" -> wrap(call.argument<ByteArray>("key")!!, reply)
                "unwrap" -> unwrap(
                    call.argument<ByteArray>("iv")!!,
                    call.argument<ByteArray>("data")!!,
                    reply,
                )
                "deleteKey" -> {
                    deleteKey()
                    reply.success(null)
                }
                else -> reply.notImplemented()
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            reply.error("invalidated", "La llave fue invalidada", null)
        } catch (e: Exception) {
            reply.error("error", e.javaClass.simpleName, null)
        }
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun status(): String {
        val manager = activity.getSystemService(BiometricManager::class.java)
            ?: return "unsupported"
        return when (manager.canAuthenticate(AUTHENTICATORS)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "available"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "notEnrolled"
            else -> "unsupported"
        }
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun wrap(plain: ByteArray, reply: OnceResult) {
        val key = createKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        authenticate(cipher, "Activar desbloqueo con huella", reply, onFailure = ::deleteKey) { c ->
            try {
                val data = c.doFinal(plain)
                reply.success(mapOf("iv" to c.iv, "data" to data))
            } finally {
                plain.fill(0)
            }
        }
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun unwrap(iv: ByteArray, data: ByteArray, reply: OnceResult) {
        val key = keyStore().getKey(ALIAS, null) as? SecretKey
            ?: throw KeyPermanentlyInvalidatedException()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        // Lanza KeyPermanentlyInvalidatedException si Android anuló la llave.
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        authenticate(cipher, "Desbloquear Cassaforte", reply, onFailure = {}) { c ->
            reply.success(c.doFinal(data))
        }
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun authenticate(
        cipher: Cipher,
        title: String,
        reply: OnceResult,
        onFailure: () -> Unit,
        onSuccess: (Cipher) -> Unit,
    ) {
        val prompt = BiometricPrompt.Builder(activity)
            .setTitle(title)
            .setSubtitle("Huella o bloqueo de pantalla del teléfono")
            .setAllowedAuthenticators(AUTHENTICATORS)
            .setConfirmationRequired(false)
            .build()
        prompt.authenticate(
            BiometricPrompt.CryptoObject(cipher),
            CancellationSignal(),
            activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    try {
                        onSuccess(result.cryptoObject?.cipher ?: cipher)
                    } catch (e: Exception) {
                        onFailure()
                        reply.error("error", e.javaClass.simpleName, null)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    onFailure()
                    when (errorCode) {
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_CANCELED ->
                            reply.error("canceled", errString.toString(), null)
                        else -> reply.error("error", errString.toString(), null)
                    }
                }
            },
        )
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun createKey(): SecretKey {
        deleteKey()
        fun spec(strongBox: Boolean) = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
            )
            .setInvalidatedByBiometricEnrollment(true)
            .setIsStrongBoxBacked(strongBox)
            .build()

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        return try {
            // Chip de seguridad dedicado (StrongBox) si el teléfono lo tiene.
            generator.init(spec(true))
            generator.generateKey()
        } catch (e: Exception) {
            deleteKey()
            generator.init(spec(false))
            generator.generateKey()
        }
    }

    private fun deleteKey() {
        try {
            keyStore().deleteEntry(ALIAS)
        } catch (e: Exception) {
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "cassaforte_vault_key"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val AUTHENTICATORS =
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
    }
}
