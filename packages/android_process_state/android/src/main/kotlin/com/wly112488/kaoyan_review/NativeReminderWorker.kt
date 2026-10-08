package com.wly112488.kaoyan_review

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

// The recovery job uses the same evaluator as the alarm receiver. It does not
// need an Activity, Flutter Engine, or Dart callback registration.
class NativeReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result =
        if (ReminderAlarmReceiver.runEvaluation(applicationContext, fromWorker = true)) {
            Result.success()
        } else {
            Result.retry()
        }
}
