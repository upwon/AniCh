package cx.xs.open

import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    private val channelName = "io.github.upwon.anich.offline/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val intent = Intent(this, DownloadForegroundService::class.java)
                when (call.method) {
                    "update" -> {
                        intent.action = DownloadForegroundService.ACTION_UPDATE
                        intent.putExtra(DownloadForegroundService.EXTRA_TITLE, call.argument<String>("title"))
                        intent.putExtra(DownloadForegroundService.EXTRA_TEXT, call.argument<String>("text"))
                        intent.putExtra(DownloadForegroundService.EXTRA_PROGRESS, call.argument<Int>("progress") ?: 0)
                        intent.putExtra(DownloadForegroundService.EXTRA_INDETERMINATE, call.argument<Boolean>("indeterminate") ?: true)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    }
                    "stop" -> {
                        intent.action = DownloadForegroundService.ACTION_STOP
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
