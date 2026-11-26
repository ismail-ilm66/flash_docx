package com.swtnoa.flashdox

import android.Manifest
import android.app.ActivityManager
import android.app.UiModeManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/// Receives images shared *into* Flash Dox from other apps (ACTION_SEND /
/// ACTION_SEND_MULTIPLE with image/*), copies them into the cache dir and hands
/// the file paths to Dart over a MethodChannel (initial intent) and an
/// EventChannel (intents that arrive while the app is already running).
class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.swtnoa.flashdox/share_in"
    private val eventChannelName = "com.swtnoa.flashdox/share_in/events"

    private var pendingPaths: List<String>? = null
    private var eventSink: EventChannel.EventSink? = null

    /// A save waiting for the storage permission (Android 9 and below).
    private var pendingSave: Pair<MethodChannel.Result, () -> Unit>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        result.success(pendingPaths ?: emptyList<String>())
                        pendingPaths = null
                    }
                    else -> result.notImplemented()
                }
            }
        // Free storage for the camera's low-space warning (round 3, P0-C).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.swtnoa.flashdox/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> try {
                        result.success(StatFs(filesDir.path).availableBytes)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Total RAM and the low-RAM flag, for the image pipeline's low-RAM
        // mode (round 6, P0-4).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.swtnoa.flashdox/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "memory" -> try {
                        val am = getSystemService(ActivityManager::class.java)
                        val info = ActivityManager.MemoryInfo()
                        am.getMemoryInfo(info)
                        result.success(mapOf("totalBytes" to info.totalMem, "lowRam" to am.isLowRamDevice))
                    } catch (e: Exception) {
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Round 11b, I3: "Save to phone" without a permission. Android 10+
        // writes through MediaStore into Pictures/Flash Dox (images) or
        // Download/Flash Dox (PDFs); Android 9 and below asks for the storage
        // permission first and writes into the same public folders.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.swtnoa.flashdox/save")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "needsPermission" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED,
                    )
                    "save" -> {
                        val path = call.argument<String>("path")!!
                        val name = call.argument<String>("name")!!
                        val mime = call.argument<String>("mime")!!
                        val image = call.argument<Boolean>("image") ?: true
                        val run = {
                            try {
                                result.success(saveFile(path, name, mime, image))
                            } catch (e: Exception) {
                                result.error("save", e.message, null)
                            }
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
                            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
                        ) {
                            run()
                        } else {
                            pendingSave = result to run
                            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), SAVE_REQUEST)
                        }
                    }
                    "open" -> try {
                        val uri = Uri.parse(call.argument<String>("uri")!!)
                        val view = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, call.argument<String>("mime"))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(Intent.createChooser(view, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                    else -> result.notImplemented()
                }
            }
        // The Android 12+ system splash is drawn before Flutter starts, so it
        // can only match the in-app theme if Android already knows it. The
        // app night mode is persisted by the OS and used for the next launch.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.swtnoa.flashdox/theme")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setNightMode" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val mode = when (call.arguments as? String) {
                                "light" -> UiModeManager.MODE_NIGHT_NO
                                "dark" -> UiModeManager.MODE_NIGHT_YES
                                else -> UiModeManager.MODE_NIGHT_AUTO
                            }
                            getSystemService(UiModeManager::class.java)?.setApplicationNightMode(mode)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    /// Writes [path] into Pictures/Flash Dox or Download/Flash Dox; returns
    /// the content uri and the folder shown to the user.
    private fun saveFile(path: String, name: String, mime: String, image: Boolean): Map<String, String> {
        val folder = if (image) "${Environment.DIRECTORY_PICTURES}/Flash Dox" else "${Environment.DIRECTORY_DOWNLOADS}/Flash Dox"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = if (image) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val uri = contentResolver.insert(collection, values) ?: throw IllegalStateException("insert failed")
            contentResolver.openOutputStream(uri)!!.use { out -> File(path).inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return mapOf("uri" to uri.toString(), "folder" to folder)
        }
        @Suppress("DEPRECATION")
        val base = Environment.getExternalStoragePublicDirectory(if (image) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS)
        val dir = File(base, "Flash Dox").apply { mkdirs() }
        var out = File(dir, name)
        var n = 2
        while (out.exists()) {
            out = File(dir, "${name.substringBeforeLast('.')} ($n).${name.substringAfterLast('.')}")
            n++
        }
        File(path).copyTo(out)
        var scanned: Uri? = null
        val lock = Object()
        MediaScannerConnection.scanFile(this, arrayOf(out.absolutePath), arrayOf(mime)) { _, uri ->
            synchronized(lock) {
                scanned = uri
                lock.notifyAll()
            }
        }
        synchronized(lock) { if (scanned == null) lock.wait(2000) }
        return mapOf("uri" to (scanned?.toString() ?: ""), "folder" to folder)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != SAVE_REQUEST) return
        val (result, run) = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) run() else result.error("permission", "denied", null)
    }

    companion object {
        private const val SAVE_REQUEST = 4711
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingPaths = extractImages(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val paths = extractImages(intent) ?: return
        val sink = eventSink
        if (sink != null) sink.success(paths) else pendingPaths = paths
    }

    private fun extractImages(intent: Intent?): List<String>? {
        if (intent == null) return null
        val type = intent.type ?: return null
        if (!type.startsWith("image/")) return null
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND ->
                listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.filterNotNull() ?: emptyList()
            else -> emptyList()
        }
        if (uris.isEmpty()) return null
        // Clear the action so a configuration change doesn't re-import.
        intent.action = null
        return uris.mapNotNull { copyToCache(it) }
    }

    private fun copyToCache(uri: Uri): String? {
        return try {
            val dir = File(cacheDir, "share_in").apply { mkdirs() }
            val ext = contentResolver.getType(uri)?.substringAfter('/')?.let {
                if (it == "jpeg") "jpg" else it
            } ?: "jpg"
            val out = File(dir, "${System.currentTimeMillis()}_${uri.hashCode()}.$ext")
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { FileOutputStream(out).use { o -> it.copyTo(o) } }
            out.absolutePath
        } catch (_: Exception) {
            null
        }
    }
}
