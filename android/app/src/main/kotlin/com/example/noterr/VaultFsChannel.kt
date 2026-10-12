package com.example.noterr

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * File access inside the user's Obsidian vault on Android ("noterr/vaultfs").
 *
 * Android doesn't let one app open another app's files, so the user picks the
 * vault folder once with the system picker; the app keeps a persistable
 * read/write permission for that folder (a tree URI) and reaches files through
 * the Storage Access Framework. Paths are relative to the picked folder, with
 * '/' separators. File work runs off the main thread.
 */
class VaultFsChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val PICK_REQUEST = 7301
        // octet-stream keeps the name exactly as given; a text/* type can make
        // the provider append another extension.
        private const val MIME = "application/octet-stream"
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pickFolder") {
            pendingPick?.error("cancelled", "Another folder pick started", null)
            pendingPick = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
            activity.startActivityForResult(intent, PICK_REQUEST)
            return
        }

        val tree = call.argument<String>("tree")
        val path = call.argument<String>("path") ?: ""
        if (tree.isNullOrBlank()) {
            result.error("no_tree", "No vault folder", null)
            return
        }
        io.execute {
            try {
                val root = DocumentFile.fromTreeUri(activity, Uri.parse(tree))
                    ?: throw IllegalStateException("Vault folder is not accessible")
                val value: Any? = when (call.method) {
                    "read" -> find(root, path)?.takeIf { it.isFile }?.let { readText(it) }
                    "write" -> { write(root, path, call.argument<String>("content") ?: ""); null }
                    "modified" -> find(root, path)?.takeIf { it.isFile }?.lastModified()
                    "list" -> find(root, path)?.takeIf { it.isDirectory }
                        ?.listFiles()?.filter { it.isFile }?.mapNotNull { it.name }
                        ?: emptyList<String>()
                    "delete" -> { find(root, path)?.delete(); null }
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("vault_io", e.message, null) }
            }
        }
    }

    /** Call from Activity.onActivityResult. Returns true if it handled it. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(uri.toString())
        } catch (e: Throwable) {
            result.error("permission", e.message, null)
        }
        return true
    }

    private fun segments(path: String) = path.split('/').filter { it.isNotEmpty() }

    private fun find(root: DocumentFile, path: String): DocumentFile? {
        var node: DocumentFile = root
        for (name in segments(path)) {
            node = node.findFile(name) ?: return null
        }
        return node
    }

    private fun write(root: DocumentFile, path: String, content: String) {
        val parts = segments(path)
        require(parts.isNotEmpty()) { "Empty path" }
        var dir = root
        for (name in parts.dropLast(1)) {
            val next = dir.findFile(name)
            dir = when {
                next == null -> dir.createDirectory(name)
                    ?: throw IllegalStateException("Could not create folder $name")
                next.isDirectory -> next
                else -> throw IllegalStateException("$name is a file, not a folder")
            }
        }
        val fileName = parts.last()
        val file = dir.findFile(fileName) ?: dir.createFile(MIME, fileName)
            ?: throw IllegalStateException("Could not create $fileName")
        // "wt" truncates, so a shorter version doesn't keep the old tail.
        activity.contentResolver.openOutputStream(file.uri, "wt")?.use {
            it.write(content.toByteArray(Charsets.UTF_8))
        } ?: throw IllegalStateException("Could not open $fileName for writing")
    }

    private fun readText(file: DocumentFile): String? =
        activity.contentResolver.openInputStream(file.uri)?.use {
            it.readBytes().toString(Charsets.UTF_8)
        }
}
