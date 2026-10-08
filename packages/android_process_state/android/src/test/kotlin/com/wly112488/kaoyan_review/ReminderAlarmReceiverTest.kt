package com.wly112488.kaoyan_review

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.content.Context
import android.content.Intent
import android.content.pm.ResolveInfo
import android.content.pm.ActivityInfo
import android.database.sqlite.SQLiteDatabase
import androidx.work.Configuration
import androidx.work.WorkManager
import com.wly112488.android_process_state.ActivityVisibility
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.shadows.ShadowLog
import org.json.JSONObject

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class ReminderAlarmReceiverTest {
    private lateinit var context: Context
    private lateinit var db: SQLiteDatabase

    @Before fun prepare() {
        ShadowLog.stream = System.out
        context = RuntimeEnvironment.getApplication()
        val launch = ResolveInfo().apply {
            activityInfo = ActivityInfo().apply {
                packageName = context.packageName
                name = "android.app.Activity"
            }
        }
        shadowOf(context.packageManager).addResolveInfoForIntent(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(context.packageName), launch)
        ActivityVisibility.onActivityPaused()
        try { WorkManager.initialize(context, Configuration.Builder().build()) } catch (_: IllegalStateException) {}
        context.deleteDatabase("kaoyan_review.db")
        db = context.openOrCreateDatabase("kaoyan_review.db", 0, null)
        db.execSQL("CREATE TABLE topics(id INTEGER PRIMARY KEY, reminder_interval_ms INTEGER, last_reminded_at_us INTEGER)")
        db.execSQL("INSERT INTO topics VALUES(1,NULL,NULL)")
        db.execSQL("CREATE TABLE review_items(id INTEGER PRIMARY KEY, content TEXT, topic_id INTEGER, enabled INTEGER, created_at_us INTEGER, last_shown_at_us INTEGER, reminder_count INTEGER)")
        db.execSQL("INSERT INTO review_items VALUES(1,'first content',1,1,1,NULL,0),(2,'second content',1,1,2,NULL,0)")
        db.execSQL("CREATE TABLE reminder_settings(id INTEGER PRIMARY KEY, enabled INTEGER, active_window_mode TEXT, start_minute INTEGER, end_minute INTEGER, reminder_interval_ms INTEGER, repeat_cooldown_ms INTEGER, scope_mode TEXT)")
        db.execSQL("INSERT INTO reminder_settings VALUES(1,1,'all_day',NULL,NULL,60000,60000,'all_topics')")
        db.execSQL("CREATE TABLE reminder_scope_topics(topic_id INTEGER)")
        db.execSQL("CREATE TABLE reminder_weekday_topics(weekday INTEGER,topic_id INTEGER)")
        db.execSQL("CREATE TABLE reminder_runtime_state(id INTEGER PRIMARY KEY, last_evaluation_at_us INTEGER, last_evaluation_outcome TEXT, last_dispatch_at_us INTEGER, last_dispatch_item_id INTEGER, last_dispatch_topic_id INTEGER, last_evaluation_source TEXT, last_worker_started_at_us INTEGER, last_worker_completed_at_us INTEGER, last_worker_outcome TEXT, last_worker_error_at_us INTEGER, last_worker_error_details TEXT, pending_dispatch_json TEXT)")
        db.execSQL("INSERT INTO reminder_runtime_state(id) VALUES(1)")
    }

    @After fun close() { if (db.isOpen) db.close() }

    private fun interruptedReservation(): Long {
        val atUs = (System.currentTimeMillis()-240000)*1000
        val pending = JSONObject()
            .put("item_id", 1).put("topic_id", 1).put("dispatch_at_us", atUs)
            .put("owner_pid", -1).put("previous_count", 0)
        for (key in listOf("previous_item_at_us", "previous_topic_at_us", "previous_dispatch_at_us",
            "previous_dispatch_item_id", "previous_dispatch_topic_id")) pending.put(key, JSONObject.NULL)
        db.execSQL("UPDATE review_items SET last_shown_at_us = ?, reminder_count = 1 WHERE id = 1", arrayOf(atUs))
        db.execSQL("UPDATE topics SET last_reminded_at_us = ? WHERE id = 1", arrayOf(atUs))
        db.execSQL("UPDATE reminder_runtime_state SET last_dispatch_at_us = ?, last_dispatch_item_id = 1, last_dispatch_topic_id = 1, pending_dispatch_json = ? WHERE id = 1", arrayOf<Any?>(atUs, pending.toString()))
        return atUs
    }

    @Test fun abandonedUnsentReservationIsRestoredBeforeSelectingContent() {
        interruptedReservation()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        assertTrue(ReminderAlarmReceiver.runEvaluation(context))
        db.rawQuery("SELECT reminder_count FROM review_items WHERE id = 2", null).use {
            assertTrue(it.moveToFirst()); assertEquals("The unsent FIFO first content must be restored", 0, it.getInt(0))
        }
        db.rawQuery("SELECT reminder_count FROM review_items WHERE id = 1", null).use {
            assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0))
        }
    }

    @Test fun acceptedReservationIsAcknowledgedWithoutRepostingWhileForeground() {
        val atUs = interruptedReservation()
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("study_reminders", "Review", NotificationManager.IMPORTANCE_HIGH))
        manager.notify(1, Notification.Builder(context, "study_reminders")
            .setSmallIcon(android.R.drawable.ic_dialog_info).setWhen(atUs/1000).build())
        ActivityVisibility.onActivityResumed()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        assertTrue(ReminderAlarmReceiver.runEvaluation(context))
        db.rawQuery("SELECT pending_dispatch_json FROM reminder_runtime_state", null).use {
            assertTrue(it.moveToFirst()); assertTrue("Accepted delivery must clear the durable reservation", it.isNull(0))
        }
        assertEquals(1, manager.activeNotifications.size)
    }

    @Test fun storedAlarmWithoutExactPermissionHasPersistentFallback() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        context.getSharedPreferences("kaoyan_review_reminder_alarm", Context.MODE_PRIVATE)
            .edit().putLong("next_at_epoch_millis", System.currentTimeMillis()+60000).commit()
        ReminderAlarmReceiver.scheduleStoredAlarm(context)
        val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork("kaoyan_review.native_recovery").get()
        assertTrue("A lost exact alarm must have a persistent successor", work.any { !it.state.isFinished })
        db.close()
    }

    @Test fun disabledReviewChannelDoesNotConsumeEitherContentHistory() {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("study_reminders", "Review", NotificationManager.IMPORTANCE_NONE))
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        assertTrue(ReminderAlarmReceiver.runEvaluation(context))
        db.rawQuery("SELECT SUM(reminder_count) FROM review_items", null).use {
            assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
        }
        db.rawQuery("SELECT last_evaluation_outcome FROM reminder_runtime_state", null).use {
            assertTrue(it.moveToFirst()); assertEquals("notificationUnavailable", it.getString(0))
        }
        db.close()
    }
}
