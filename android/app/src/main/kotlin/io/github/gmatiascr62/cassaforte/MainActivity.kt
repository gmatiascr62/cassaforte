package io.github.gmatiascr62.cassaforte

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var backupFiles: BackupFilesChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Impide capturas y grabaciones de pantalla, y oculta el contenido
        // en la vista de aplicaciones recientes.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "cassaforte/biometric")
            .setMethodCallHandler(BiometricChannel(this))
        val files = BackupFilesChannel(this)
        backupFiles = files
        MethodChannel(messenger, "cassaforte/files").setMethodCallHandler(files)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "copySensitive" -> {
                            val text = call.argument<String>("text") ?: ""
                            result.success(copySensitive(text))
                        }
                        "clearIfUnchanged" -> {
                            val token = call.argument<Any>("token")
                            val text = call.argument<String>("text") ?: ""
                            result.success(clearIfUnchanged(token, text))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("clipboard", e.javaClass.simpleName, null)
                }
            }
    }

    // Resultado del selector de archivos (copias de seguridad).
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupFiles?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun clipboard(): ClipboardManager =
        getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    /**
     * Copia el texto marcándolo como sensible (Android 13+ no lo muestra en
     * la vista previa del portapapeles). Devuelve la marca de tiempo de la
     * copia (Android 8+) para poder reconocerla después sin leer su texto.
     */
    private fun copySensitive(text: String): Long? {
        val clip = ClipData.newPlainText(CLIP_LABEL, text)
        val extras = PersistableBundle()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            extras.putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        } else {
            extras.putBoolean("android.content.extra.IS_SENSITIVE", true)
        }
        clip.description.extras = extras
        val manager = clipboard()
        manager.setPrimaryClip(clip)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return manager.primaryClipDescription?.timestamp
        }
        return null
    }

    /**
     * Borra el portapapeles solo si todavía contiene la copia hecha por la
     * aplicación. Android 10+ no deja consultarlo en segundo plano: en ese
     * caso devuelve "unavailable" y Dart lo reintenta al volver.
     */
    private fun clearIfUnchanged(token: Any?, text: String): String {
        val manager = clipboard()
        val description = manager.primaryClipDescription ?: return "unavailable"
        if (description.label?.toString() != CLIP_LABEL) return "changed"
        val expected = (token as? Number)?.toLong()
        val same = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && expected != null) {
            description.timestamp == expected
        } else {
            val clip = manager.primaryClip ?: return "unavailable"
            clip.itemCount > 0 && clip.getItemAt(0).text?.toString() == text
        }
        if (!same) return "changed"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.clearPrimaryClip()
        } else {
            manager.setPrimaryClip(ClipData.newPlainText("", ""))
        }
        return "cleared"
    }

    companion object {
        private const val CHANNEL = "cassaforte/clipboard"
        private const val CLIP_LABEL = "Cassaforte"
    }
}
