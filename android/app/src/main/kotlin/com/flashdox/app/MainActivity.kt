package com.flashdox.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
    private val methodChannelName = "com.flashdox.app/share_in"
    private val eventChannelName = "com.flashdox.app/share_in/events"

    private var pendingPaths: List<String>? = null
    private var eventSink: EventChannel.EventSink? = null

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

    private fun copyToCache(uri: Uri): String? = try {
        val dir = File(cacheDir, "share_in").apply { mkdirs() }
        val ext = contentResolver.getType(uri)?.substringAfter('/')?.let {
            if (it == "jpeg") "jpg" else it
        } ?: "jpg"
        val out = File(dir, "${System.currentTimeMillis()}_${uri.hashCode()}.$ext")
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(out).use { input.copyTo(it) }
        } ?: return null
        out.absolutePath
    } catch (_: Exception) {
        null
    }
}
