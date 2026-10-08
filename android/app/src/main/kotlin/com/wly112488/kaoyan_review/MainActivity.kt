package com.wly112488.kaoyan_review

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.wly112488.android_process_state.ActivityVisibility
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationTapChannel: MethodChannel? = null
    private var pendingReviewItemId: Int? = null

    override fun onResume() {
        super.onResume()
        ActivityVisibility.onActivityResumed()
    }

    override fun onPause() {
        ActivityVisibility.onActivityPaused()
        super.onPause()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingReviewItemId = intent?.getIntExtra("reviewItemId", -1)?.takeIf { it > 0 }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationTapChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kaoyan_review/notification_tap",
        )
        notificationTapChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingItemId") {
                result.success(pendingReviewItemId)
                pendingReviewItemId = null
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaoyan_review/settings")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getDeviceInfo" -> {
                            val packageInfo = packageManager.getPackageInfo(packageName, 0)
                            @Suppress("DEPRECATION")
                            val versionCode = packageInfo.versionCode
                            result.success(mapOf(
                                "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
                                "androidVersion" to Build.VERSION.RELEASE,
                                "appVersion" to packageInfo.versionName,
                                "appBuild" to versionCode.toString(),
                            ))
                        }
                        "openNotificationSettings" -> {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                }
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                }
                            }
                            startActivity(intent)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("settings_unavailable", error.message, null)
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val itemId = intent.getIntExtra("reviewItemId", -1).takeIf { it > 0 } ?: return
        pendingReviewItemId = itemId
        notificationTapChannel?.invokeMethod("onTap", itemId)
    }
}
