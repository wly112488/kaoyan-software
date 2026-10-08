package com.wly112488.android_process_state

import com.wly112488.kaoyan_review.ReminderAlarmReceiver
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidProcessStatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var alarmChannel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "kaoyan_review/android_process_state")
        channel.setMethodCallHandler(this)
        val context = binding.applicationContext
        alarmChannel = MethodChannel(binding.binaryMessenger, "kaoyan_review/reminder_alarm")
        alarmChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "supportsNotificationChannels" -> result.success(android.os.Build.VERSION.SDK_INT >= 26)
                    "wasSubmitted" -> result.success(ReminderAlarmReceiver.wasSubmitted(
                        context,
                        call.argument<Number>("itemId")!!.toInt(),
                        call.argument<Number>("dispatchAtMillis")!!.toLong(),
                    ))
                    "schedule" -> {
                        val at = call.argument<Number>("atEpochMillis")?.toLong()
                            ?: throw IllegalArgumentException("Missing alarm time")
                        result.success(ReminderAlarmReceiver.schedule(
                            context, at, call.argument<Boolean>("keepExisting") == true,
                        ))
                    }
                    "cancel" -> {
                        ReminderAlarmReceiver.cancel(context)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("reminder_alarm_failed", error.message, null)
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isForeground" -> {
                result.success(ActivityVisibility.isActivityResumed())
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        alarmChannel.setMethodCallHandler(null)
    }
}
