package io.github.gmatiascr62.cassaforte

import io.flutter.plugin.common.MethodChannel

/** Garantiza que cada llamada de Flutter reciba una sola respuesta. */
class OnceResult(private val inner: MethodChannel.Result) {
    private var done = false

    fun success(value: Any?) {
        if (done) return
        done = true
        inner.success(value)
    }

    fun error(code: String, message: String?, details: Any?) {
        if (done) return
        done = true
        inner.error(code, message, details)
    }

    fun notImplemented() {
        if (done) return
        done = true
        inner.notImplemented()
    }
}
