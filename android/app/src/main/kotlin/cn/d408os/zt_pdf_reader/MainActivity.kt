package cn.d408os.zt_pdf_reader

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Bridges "open with" style intents (content:// or file:// PDFs, plus the
/// zt408os:// custom scheme) into Flutter by copying the stream into the app
/// cache and handing the resulting absolute path to Dart.
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "cn.d408os.zt_pdf_reader/intent"
    }

    private var channel: MethodChannel? = null
    private var pendingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    result.success(pendingPath)
                    pendingPath = null
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_VIEW) return
        val uri: Uri = intent.data ?: return
        Thread {
            val path = runCatching { copyToCache(uri) }.getOrNull()
            if (path == null) return@Thread
            runOnUiThread {
                pendingPath = path
                channel?.invokeMethod("onFileOpened", path)
            }
        }.start()
    }

    private fun copyToCache(uri: Uri): String? {
        val dir = File(cacheDir, "incoming")
        if (!dir.exists() && !dir.mkdirs()) return null
        val rawName = displayName(uri) ?: "document.pdf"
        val safeName = rawName.replace(Regex("[^0-9A-Za-z._\\-]"), "_")
        val out = File(dir, safeName)
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        return out.absolutePath
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        runCatching {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) return cursor.getString(index)
            }
        }
        return uri.lastPathSegment
    }
}
