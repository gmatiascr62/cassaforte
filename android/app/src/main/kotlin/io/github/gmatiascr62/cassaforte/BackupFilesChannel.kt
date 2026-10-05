package io.github.gmatiascr62.cassaforte

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream

/**
 * Guarda y abre copias de seguridad con el selector de archivos del sistema
 * (Storage Access Framework). No necesita permisos de almacenamiento.
 */
class BackupFilesChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var pending: OnceResult? = null
    private var pendingBytes: ByteArray? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = OnceResult(result)
        if (pending != null) {
            reply.error("busy", "Ya hay una operación en curso", null)
            return
        }
        when (call.method) {
            "save" -> {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "cassaforte.cassaforte")
                }
                pendingBytes = call.argument<ByteArray>("bytes")
                pending = reply
                activity.startActivityForResult(intent, REQUEST_SAVE)
            }
            "open" -> {
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                }
                pending = reply
                activity.startActivityForResult(intent, REQUEST_OPEN)
            }
            else -> reply.notImplemented()
        }
    }

    /** Devuelve `true` si el resultado era para este canal. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SAVE && requestCode != REQUEST_OPEN) return false
        val reply = pending ?: return true
        val bytes = pendingBytes
        pending = null
        pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            reply.success(if (requestCode == REQUEST_SAVE) false else null)
            return true
        }
        try {
            if (requestCode == REQUEST_SAVE) {
                val out = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IOException("No se pudo abrir el destino")
                out.use { it.write(bytes ?: ByteArray(0)) }
                reply.success(true)
            } else {
                val input = activity.contentResolver.openInputStream(uri)
                    ?: throw IOException("No se pudo abrir el archivo")
                reply.success(input.use { readLimited(it) })
            }
        } catch (e: Exception) {
            reply.error("io", e.javaClass.simpleName, null)
        }
        return true
    }

    private fun readLimited(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            out.write(buffer, 0, n)
            if (out.size() > MAX_BYTES) throw IOException("Archivo demasiado grande")
        }
        return out.toByteArray()
    }

    companion object {
        private const val REQUEST_SAVE = 4101
        private const val REQUEST_OPEN = 4102
        private const val MAX_BYTES = 32 * 1024 * 1024
    }
}
