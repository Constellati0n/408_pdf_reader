package cn.d408os.zt_pdf_reader

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Bridges inbound intents into Flutter.
///
/// Two kinds are handled: "open with" PDFs (`content://` or `file://`), which
/// are copied into the app cache and handed to Dart as an absolute path, and
/// `zt408os://<bookCode>?page=&highlight=` jump requests coming from the
/// 408os.cn website, which are forwarded as a map.
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "cn.d408os.zt_pdf_reader/intent"
        private const val SCHEME = "zt408os"
    }

    private var channel: MethodChannel? = null
    private var pendingPath: String? = null
    private var pendingDeepLink: Map<String, Any?>? = null

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
                "getInitialDeepLink" -> {
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
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

        if (SCHEME.equals(uri.scheme, ignoreCase = true)) {
            val link = parseDeepLink(uri)
            runOnUiThread {
                pendingDeepLink = link
                channel?.invokeMethod("onDeepLink", link)
            }
            return
        }

        Thread {
            val path = runCatching { copyToCache(uri) }.getOrNull() ?: return@Thread
            runOnUiThread {
                pendingPath = path
                channel?.invokeMethod("onFileOpened", path)
            }
        }.start()
    }

    /// Normalises both documented link shapes into one map:
    /// `zt408os://<code>?page=&highlight=` and `zt408os://?book=<code>&...`.
    private fun parseDeepLink(uri: Uri): Map<String, Any?> {
        val book = sequenceOf(
            uri.getQueryParameter("book"),
            uri.host,
            uri.schemeSpecificPart?.substringBefore('?')?.trim('/'),
        ).mapNotNull { it?.trim() }.firstOrNull { it.isNotEmpty() } ?: ""

        return mapOf(
            "book" to book,
            "page" to (uri.getQueryParameter("page")?.toIntOrNull() ?: 1),
            "highlight" to (uri.getQueryParameter("highlight") ?: ""),
        )
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
