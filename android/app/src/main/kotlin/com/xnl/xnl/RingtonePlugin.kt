package com.xnl.xnl

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * 铃声桥：系统铃声选择、本地音乐选择（SAF）、试听播放。
 *
 * 选中的 content:// 音频会拷贝到 filesDir/ringtones/ 并回传绝对路径，
 * 闹钟内核只认 assets 路径与本地文件路径，拷贝一次即可长期使用。
 */
class RingtonePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val CHANNEL = "com.xnl.xnl/ringtone"
        private const val REQ_RINGTONE = 0x7111
        private const val REQ_AUDIO = 0x7112
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** 用户选择器返回前挂起的调用结果（同时只允许一个选择器）。 */
    private var pendingResult: MethodChannel.Result? = null
    private var pendingKind = 0

    /** 试听播放器。 */
    private var player: MediaPlayer? = null

    private val activity: Activity?
        get() = activityBinding?.activity

    // ---- FlutterPlugin ----

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopPreviewInternal()
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    // ---- ActivityAware ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    // ---- MethodChannel.MethodCallHandler ----

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickRingtone" -> pickRingtone(result)
            "pickAudioFile" -> pickAudioFile(result)
            "preview" -> preview(call.arguments as? String, result)
            "stopPreview" -> {
                stopPreviewInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun pickRingtone(result: MethodChannel.Result) {
        val act = activity ?: return result.error("NO_ACTIVITY", "需要在界面中调用", null)
        if (pendingResult != null) return result.error("BUSY", "已有选择器在打开", null)
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_TYPE,
                RingtoneManager.TYPE_ALARM or RingtoneManager.TYPE_NOTIFICATION or
                    RingtoneManager.TYPE_RINGTONE,
            )
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "选择闹钟铃声")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
        }
        pendingResult = result
        pendingKind = REQ_RINGTONE
        act.startActivityForResult(intent, REQ_RINGTONE)
    }

    private fun pickAudioFile(result: MethodChannel.Result) {
        val act = activity ?: return result.error("NO_ACTIVITY", "需要在界面中调用", null)
        if (pendingResult != null) return result.error("BUSY", "已有选择器在打开", null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pendingResult = result
        pendingKind = REQ_AUDIO
        act.startActivityForResult(intent, REQ_AUDIO)
    }

    // ---- PluginRegistry.ActivityResultListener ----

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_RINGTONE && requestCode != REQ_AUDIO) return false
        val result = pendingResult
        pendingResult = null
        pendingKind = 0
        if (result == null) return true
        if (resultCode != Activity.RESULT_OK || data == null) {
            // 用户取消：回 null，Dart 侧保持原选择
            result.success(null)
            return true
        }
        try {
            val uri: Uri? = if (requestCode == REQ_RINGTONE) {
                @Suppress("DEPRECATION")
                data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            } else {
                data.data
            }
            if (uri == null) {
                result.success(null)
                return true
            }
            val name = queryDisplayName(uri) ?: if (requestCode == REQ_RINGTONE) "系统铃声" else "本地音乐"
            val file = copyUriToPrivate(uri, name)
            result.success(mapOf("name" to name, "path" to file.absolutePath))
        } catch (e: Exception) {
            result.error("COPY_FAILED", e.message, null)
        }
        return true
    }

    // ---- 内部工具 ----

    private fun queryDisplayName(uri: Uri): String? {
        val ctx = appContext ?: return null
        if (uri.scheme == "content") {
            ctx.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) return cursor.getString(idx)
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    /** 把 content:// 音频拷进应用私有目录；同一 URI 重选覆盖写，不堆积副本。 */
    private fun copyUriToPrivate(uri: Uri, displayName: String): File {
        val ctx = appContext ?: error("no context")
        val dir = File(ctx.filesDir, "ringtones").apply { mkdirs() }
        val safe = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "ringtone" }
        val hash = Integer.toHexString(uri.toString().hashCode())
        val target = File(dir, "${hash}_$safe")
        val input = ctx.contentResolver.openInputStream(uri)
            ?: error("无法读取所选音频")
        input.use { src ->
            target.outputStream().use { dst -> src.copyTo(dst) }
        }
        return target
    }

    /** 试听：`assets/...` 走 flutter_assets，其余按本地文件路径播放。 */
    private fun preview(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) return result.error("BAD_ARGS", "缺少铃声路径", null)
        val ctx = appContext ?: return result.error("NO_CONTEXT", "插件未初始化", null)
        try {
            stopPreviewInternal()
            val p = MediaPlayer()
            if (path.startsWith("assets/")) {
                ctx.assets.openFd("flutter_assets/$path").use { afd ->
                    p.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                }
            } else {
                p.setDataSource(path)
            }
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            p.isLooping = false
            p.prepare()
            p.start()
            player = p
            result.success(null)
        } catch (e: Exception) {
            stopPreviewInternal()
            result.error("PREVIEW_FAILED", e.message, null)
        }
    }

    private fun stopPreviewInternal() {
        val p = player ?: return
        player = null
        try {
            p.stop()
        } catch (_: Exception) {
        }
        try {
            p.release()
        } catch (_: Exception) {
        }
    }
}
