package com.wly112488.kaoyan_review

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import android.util.Log
import com.wly112488.android_process_state.ActivityVisibility
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

private const val REMINDER_ALARM_ID = 0x4B5256
private const val REMINDER_CHANNEL_ID = "study_reminders"
private const val REMINDER_CHANNEL_NAME = "学习提醒"
private const val REMINDER_PREFS = "kaoyan_review_reminder_alarm"
private const val REMINDER_KEY_AT = "next_at_epoch_millis"
private const val REVIEW_PAYLOAD_KEY = "reviewItemId"

class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.i("ReminderAlarmReceiver", "received action=${intent?.action}")
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED ||
            intent?.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            scheduleStoredAlarm(context)
            return
        }
        evaluateAndNotify(context)
    }

    companion object {
        fun schedule(context: Context, atEpochMillis: Long): Boolean {
            val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return false
            val canScheduleExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                alarmManager.canScheduleExactAlarms()
            Log.i("ReminderAlarmBridge", "canScheduleExactAlarms=$canScheduleExact")
            if (!canScheduleExact) return false

            context.getSharedPreferences(REMINDER_PREFS, Context.MODE_PRIVATE)
                .edit().putLong(REMINDER_KEY_AT, atEpochMillis).apply()
            val pending = alarmPendingIntent(context)
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                atEpochMillis,
                pending,
            )
            Log.i("ReminderAlarmBridge", "exact alarm registered for $atEpochMillis")
            return true
        }

        fun cancel(context: Context) {
            context.getSharedPreferences(REMINDER_PREFS, Context.MODE_PRIVATE)
                .edit().remove(REMINDER_KEY_AT).apply()
            context.getSystemService(AlarmManager::class.java)?.cancel(alarmPendingIntent(context))
        }

        fun scheduleStoredAlarm(context: Context) {
            val at = context.getSharedPreferences(REMINDER_PREFS, Context.MODE_PRIVATE)
                .getLong(REMINDER_KEY_AT, -1L)
            if (at > 0L) schedule(context, maxOf(at, System.currentTimeMillis() + 1_000L))
        }

        private fun alarmPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, ReminderAlarmReceiver::class.java)
                .setAction("${context.packageName}.REMINDER_ALARM")
            return PendingIntent.getBroadcast(
                context,
                REMINDER_ALARM_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun evaluateAndNotify(context: Context) {
            var db: SQLiteDatabase? = null
            var dispatchReservation: DispatchReservation? = null
            var notificationSubmitted = false
            try {
                val databaseFile = context.getDatabasePath("kaoyan_review.db")
                if (!databaseFile.exists()) return
                db = SQLiteDatabase.openDatabase(
                    databaseFile.path,
                    null,
                    SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
                )
                db.rawQuery("PRAGMA busy_timeout = 5000", null).use { it.moveToFirst() }
                val nowMillis = System.currentTimeMillis()
                val now = LocalDateTime.ofInstant(
                    java.time.Instant.ofEpochMilli(nowMillis),
                    ZoneId.systemDefault(),
                )
                val evaluation = db.transaction {
                    val settings = readSettings(db)
                    if (!settings.enabled) {
                        updateRuntime(db, nowMillis, "reminderDisabled", null)
                        return@transaction Evaluation(null, null)
                    }

                    val runtime = readRuntime(db)
                    val appInForeground = ActivityVisibility.isActivityResumed()
                    if (appInForeground) {
                        updateRuntime(db, nowMillis, "foregroundSuppressed", "scheduled_alarm")
                        return@transaction Evaluation(
                            null,
                            nextOpportunity(db, settings, runtime, now, nowMillis + settings.intervalMillis)?.atMillis,
                        )
                    }

                    if (!notificationsAvailable(context)) {
                        updateRuntime(db, nowMillis, "notificationUnavailable", "scheduled_alarm")
                        return@transaction Evaluation(
                            null,
                            nextOpportunity(db, settings, runtime, now, nowMillis + settings.intervalMillis)?.atMillis,
                        )
                    }

                    val due = nextOpportunity(db, settings, runtime, now, nowMillis)
                    val candidate = due?.candidate
                    if (candidate == null || due.atMillis > nowMillis) {
                        updateRuntime(db, nowMillis, "noEligibleItem", "scheduled_alarm")
                        return@transaction Evaluation(null, due?.atMillis)
                    }

                    val previousTopicLastRemindedAtMillis = db.rawQuery(
                        "SELECT last_reminded_at_us FROM topics WHERE id = ?",
                        arrayOf(candidate.topicId.toString()),
                    ).use { cursor ->
                        if (!cursor.moveToFirst() || cursor.isNull(0)) null
                        else cursor.getLong(0) / 1_000L
                    }
                    db.execSQL(
                        "UPDATE review_items SET last_shown_at_us = ?, reminder_count = reminder_count + 1 WHERE id = ?",
                        arrayOf<Any?>(nowMillis * 1_000L, candidate.id),
                    )
                    db.execSQL(
                        "UPDATE topics SET last_reminded_at_us = ? WHERE id = ?",
                        arrayOf<Any?>(nowMillis * 1_000L, candidate.topicId),
                    )
                    db.execSQL(
                        """UPDATE reminder_runtime_state
                           SET last_evaluation_at_us = ?, last_evaluation_outcome = 'notification_submitted',
                               last_dispatch_at_us = ?, last_dispatch_item_id = ?, last_dispatch_topic_id = ?,
                               last_evaluation_source = 'scheduled_alarm', last_worker_started_at_us = ?,
                               last_worker_completed_at_us = ?, last_worker_outcome = 'nativeAlarmCompleted',
                               last_worker_error_at_us = NULL, last_worker_error_details = NULL
                           WHERE id = 1""".trimIndent(),
                        arrayOf<Any?>(
                            nowMillis * 1_000L,
                            nowMillis * 1_000L,
                            candidate.id,
                            candidate.topicId,
                            nowMillis * 1_000L,
                            nowMillis * 1_000L,
                        ),
                    )
                    dispatchReservation = DispatchReservation(
                        candidate = candidate,
                        dispatchedAtMillis = nowMillis,
                        previousTopicLastRemindedAtMillis = previousTopicLastRemindedAtMillis,
                        previousRuntime = runtime,
                    )
                    val next = nextOpportunity(db, settings, readRuntime(db), now, nowMillis + 1L)
                    Evaluation(candidate, next?.atMillis)
                }

                if (evaluation.candidate != null) {
                    postReviewNotification(context, evaluation.candidate)
                    notificationSubmitted = true
                    Log.i(
                        "ReminderAlarmReceiver",
                        "submitted review notification itemId=${evaluation.candidate.id}",
                    )
                }
                val nextAt = evaluation.nextAtMillis
                if (nextAt != null) {
                    schedule(context, maxOf(nextAt, System.currentTimeMillis() + 1_000L))
                } else {
                    cancel(context)
                }
            } catch (error: Throwable) {
                Log.e("ReminderAlarmReceiver", "evaluation failed", error)
                if (!notificationSubmitted && db != null && dispatchReservation != null) {
                    rollbackDispatch(db, dispatchReservation!!)
                }
                recordFailure(db, error)
                schedule(context, System.currentTimeMillis() + 60_000L)
            } finally {
                db?.close()
            }
        }

        private fun SQLiteDatabase.transaction(block: () -> Evaluation): Evaluation {
            beginTransaction()
            return try {
                val result = block()
                setTransactionSuccessful()
                result
            } finally {
                endTransaction()
            }
        }

        private fun readSettings(db: SQLiteDatabase): Settings {
            db.rawQuery(
                "SELECT enabled, active_window_mode, start_minute, end_minute, reminder_interval_ms, repeat_cooldown_ms, scope_mode FROM reminder_settings WHERE id = 1",
                null,
            ).use { cursor ->
                check(cursor.moveToFirst()) { "ReminderSettings singleton is missing" }
                val selectedTopics = mutableSetOf<Int>()
                if (cursor.getString(6) == "selected_topics") {
                    db.rawQuery("SELECT topic_id FROM reminder_scope_topics", null).use { selected ->
                        while (selected.moveToNext()) selectedTopics += selected.getInt(0)
                    }
                }
                val weekdayTopics = mutableMapOf<Int, MutableSet<Int>>()
                db.rawQuery("SELECT weekday, topic_id FROM reminder_weekday_topics", null).use { rows ->
                    while (rows.moveToNext()) {
                        weekdayTopics.getOrPut(rows.getInt(0)) { mutableSetOf() } += rows.getInt(1)
                    }
                }
                return Settings(
                    enabled = cursor.getInt(0) == 1,
                    windowMode = cursor.getString(1),
                    startMinute = if (cursor.isNull(2)) null else cursor.getInt(2),
                    endMinute = if (cursor.isNull(3)) null else cursor.getInt(3),
                    intervalMillis = cursor.getLong(4),
                    cooldownMillis = cursor.getLong(5),
                    allTopics = cursor.getString(6) == "all_topics",
                    selectedTopics = selectedTopics,
                    weekdayTopics = weekdayTopics,
                )
            }
        }

        private fun readRuntime(db: SQLiteDatabase): Runtime {
            db.rawQuery(
                "SELECT last_evaluation_at_us, last_evaluation_outcome, last_dispatch_at_us, last_dispatch_item_id, last_dispatch_topic_id FROM reminder_runtime_state WHERE id = 1",
                null,
            ).use { cursor ->
                check(cursor.moveToFirst()) { "Reminder runtime singleton is missing" }
                return Runtime(
                    lastEvaluationMillis = if (cursor.isNull(0)) null else cursor.getLong(0) / 1_000L,
                    lastEvaluationOutcome = if (cursor.isNull(1)) null else cursor.getString(1),
                    lastDispatchMillis = if (cursor.isNull(2)) null else cursor.getLong(2) / 1_000L,
                    lastDispatchItemId = if (cursor.isNull(3)) null else cursor.getInt(3),
                    lastDispatchTopicId = if (cursor.isNull(4)) null else cursor.getInt(4),
                )
            }
        }

        private fun nextOpportunity(
            db: SQLiteDatabase,
            settings: Settings,
            runtime: Runtime,
            now: LocalDateTime,
            notBeforeMillis: Long,
        ): Due? {
            val allItems = mutableListOf<Item>()
            db.rawQuery(
                "SELECT id, content, topic_id, enabled, created_at_us, last_shown_at_us, reminder_count FROM review_items ORDER BY id ASC",
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    allItems += Item(
                        id = cursor.getInt(0),
                        content = cursor.getString(1),
                        topicId = cursor.getInt(2),
                        enabled = cursor.getInt(3) == 1,
                        createdAtMillis = cursor.getLong(4) / 1_000L,
                        lastShownAtMillis = if (cursor.isNull(5)) null else cursor.getLong(5) / 1_000L,
                        reminderCount = cursor.getInt(6),
                    )
                }
            }
            val topics = mutableMapOf<Int, Topic>()
            db.rawQuery("SELECT id, reminder_interval_ms, last_reminded_at_us FROM topics", null).use { cursor ->
                while (cursor.moveToNext()) {
                    topics[cursor.getInt(0)] = Topic(
                        intervalMillis = if (cursor.isNull(1)) settings.intervalMillis else maxOf(settings.intervalMillis, cursor.getLong(1)),
                        lastRemindedAtMillis = if (cursor.isNull(2)) null else cursor.getLong(2) / 1_000L,
                    )
                }
            }

            val activeItems = allItems.filter { item ->
                item.enabled && (settings.allTopics || item.topicId in settings.selectedTopics)
            }
            if (activeItems.isEmpty()) return null
            var globalDue = runtime.lastDispatchMillis?.plus(settings.intervalMillis) ?: notBeforeMillis
            if (runtime.lastEvaluationOutcome == "notificationUnavailable") {
                val evaluationDue = runtime.lastEvaluationMillis?.plus(settings.intervalMillis)
                if (evaluationDue != null) globalDue = maxOf(globalDue, evaluationDue)
            }

            val zone = ZoneId.systemDefault()
            val today = LocalDateTime.ofInstant(java.time.Instant.ofEpochMilli(notBeforeMillis), zone).toLocalDate()
            var best: Due? = null
            for (offset in 0..37) {
                val date = today.plusDays(offset.toLong())
                val weekdayTopics = settings.weekdayTopics[date.dayOfWeek.value]
                if (settings.weekdayTopics.isNotEmpty() && weekdayTopics == null) continue
                val daily = activeItems.filter { item -> weekdayTopics == null || item.topicId in weekdayTopics }
                if (daily.isEmpty()) continue
                val unseen = daily.filter { it.lastShownAtMillis == null }
                val candidates = if (unseen.isNotEmpty()) unseen else daily
                val round = settings.intervalMillis * daily.size.toLong()
                val effectiveCooldown = minOf(settings.cooldownMillis, round)
                for (item in candidates) {
                    val topic = topics[item.topicId] ?: continue
                    var dueAt = globalDue
                    topic.lastRemindedAtMillis?.let { dueAt = maxOf(dueAt, it + topic.intervalMillis) }
                    item.lastShownAtMillis?.let {
                        dueAt = maxOf(dueAt, it + maxOf(effectiveCooldown, topic.intervalMillis))
                    }
                    val windowStart: Long
                    val windowEnd: Long
                    if (settings.windowMode == "bounded") {
                        val startMinute = settings.startMinute ?: continue
                        val endMinute = settings.endMinute ?: continue
                        windowStart = date.atStartOfDay(zone).plusMinutes(startMinute.toLong()).toInstant().toEpochMilli()
                        windowEnd = date.atStartOfDay(zone).plusMinutes(endMinute.toLong()).toInstant().toEpochMilli()
                        dueAt = maxOf(dueAt, windowStart)
                        if (dueAt >= windowEnd) continue
                    } else {
                        windowStart = date.atStartOfDay(zone).toInstant().toEpochMilli()
                        windowEnd = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
                        dueAt = maxOf(dueAt, windowStart)
                        if (dueAt >= windowEnd) continue
                    }
                    if (dueAt < notBeforeMillis) dueAt = notBeforeMillis
                    val itemDue = Due(item, dueAt)
                    if (best == null || itemDue.atMillis < best!!.atMillis) best = itemDue
                }
            }
            if (best == null) return null
            val sameTime = activeItems.filter { item ->
                if (best!!.atMillis > now.atZone(zone).toInstant().toEpochMilli()) return@filter false
                val weekdayTopics = settings.weekdayTopics[LocalDateTime.ofInstant(java.time.Instant.ofEpochMilli(best!!.atMillis), zone).dayOfWeek.value]
                (weekdayTopics == null || item.topicId in weekdayTopics) &&
                    (settings.allTopics || item.topicId in settings.selectedTopics)
            }
            val dueNow = sameTime.filter { itDueNow(it, topics, settings, runtime, best!!.atMillis, sameTime.size) }
            val chosen = (if (dueNow.any { it.lastShownAtMillis == null }) {
                dueNow.filter { it.lastShownAtMillis == null }.sortedWith(compareBy<Item> { it.createdAtMillis }.thenBy { it.id })
            } else {
                dueNow.sortedWith(compareBy<Item> { it.reminderCount }.thenBy { it.lastShownAtMillis ?: Long.MIN_VALUE }.thenBy { it.id })
            }).firstOrNull() ?: best!!.candidate
            return Due(chosen, best!!.atMillis)
        }

        private fun itDueNow(
            item: Item,
            topics: Map<Int, Topic>,
            settings: Settings,
            runtime: Runtime,
            atMillis: Long,
            activeCount: Int,
        ): Boolean {
            val globalDue = runtime.lastDispatchMillis?.plus(settings.intervalMillis) ?: Long.MIN_VALUE
            if (atMillis < globalDue) return false
            val topic = topics[item.topicId] ?: return false
            if (topic.lastRemindedAtMillis != null && atMillis < topic.lastRemindedAtMillis + topic.intervalMillis) return false
            val cooldown = minOf(settings.cooldownMillis, settings.intervalMillis * activeCount.toLong())
            val itemDue = item.lastShownAtMillis?.plus(maxOf(cooldown, topic.intervalMillis))
            return itemDue == null || atMillis >= itemDue
        }

        private fun updateRuntime(db: SQLiteDatabase, nowMillis: Long, outcome: String, source: String?) {
            db.execSQL(
                """UPDATE reminder_runtime_state SET last_evaluation_at_us = ?, last_evaluation_outcome = ?,
                   last_evaluation_source = ?, last_worker_started_at_us = ?, last_worker_completed_at_us = ?,
                   last_worker_outcome = ?, last_worker_error_at_us = NULL, last_worker_error_details = NULL
                   WHERE id = 1""".trimIndent(),
                arrayOf<Any?>(nowMillis * 1_000L, outcome, source, nowMillis * 1_000L, nowMillis * 1_000L, outcome),
            )
        }

        private fun recordFailure(db: SQLiteDatabase?, error: Throwable) {
            if (db == null || !db.isOpen) return
            try {
                val at = System.currentTimeMillis() * 1_000L
                db.execSQL(
                    """UPDATE reminder_runtime_state SET last_evaluation_at_us = ?,
                       last_evaluation_outcome = 'workerFailure', last_evaluation_source = 'scheduled_alarm',
                       last_worker_error_at_us = ?, last_worker_error_details = ?,
                       last_worker_completed_at_us = ?, last_worker_outcome = 'nativeAlarmFailure'
                       WHERE id = 1""".trimIndent(),
                    arrayOf<Any?>(at, at, "${error.javaClass.simpleName}: ${error.message}", at),
                )
            } catch (_: Throwable) {
                // The original database error remains the cause of the missed run.
            }
        }

        private fun rollbackDispatch(db: SQLiteDatabase, reservation: DispatchReservation) {
            if (!db.isOpen) return
            try {
                db.transaction {
                    val dispatchedAtMicros = reservation.dispatchedAtMillis * 1_000L
                    db.execSQL(
                        "UPDATE review_items SET last_shown_at_us = ?, reminder_count = ? WHERE id = ? AND last_shown_at_us = ?",
                        arrayOf<Any?>(
                            reservation.candidate.lastShownAtMillis?.times(1_000L),
                            reservation.candidate.reminderCount,
                            reservation.candidate.id,
                            dispatchedAtMicros,
                        ),
                    )
                    db.execSQL(
                        "UPDATE topics SET last_reminded_at_us = ? WHERE id = ? AND last_reminded_at_us = ?",
                        arrayOf<Any?>(
                            reservation.previousTopicLastRemindedAtMillis?.times(1_000L),
                            reservation.candidate.topicId,
                            dispatchedAtMicros,
                        ),
                    )
                    val previous = reservation.previousRuntime
                    db.execSQL(
                        """UPDATE reminder_runtime_state
                           SET last_dispatch_at_us = ?, last_dispatch_item_id = ?, last_dispatch_topic_id = ?
                           WHERE id = 1 AND last_dispatch_at_us = ? AND last_dispatch_item_id = ?""".trimIndent(),
                        arrayOf<Any?>(
                            previous.lastDispatchMillis?.times(1_000L),
                            previous.lastDispatchItemId,
                            previous.lastDispatchTopicId,
                            dispatchedAtMicros,
                            reservation.candidate.id,
                        ),
                    )
                    Evaluation(null, null)
                }
            } catch (rollbackError: Throwable) {
                Log.e("ReminderAlarmReceiver", "failed to roll back unsent notification", rollbackError)
            }
        }

        private fun notificationsAvailable(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return false
            return context.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() == true
        }

        private fun postReviewNotification(context: Context, item: Item) {
            val manager = checkNotNull(context.getSystemService(NotificationManager::class.java)) {
                "NotificationManager is unavailable"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(REMINDER_CHANNEL_ID, REMINDER_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH),
                )
            }
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launchIntent.putExtra(REVIEW_PAYLOAD_KEY, item.id)
            val contentIntent = PendingIntent.getActivity(
                context,
                item.id,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, REMINDER_CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(R.drawable.ic_stat_review)
                .setContentTitle("考研碎片复习")
                .setContentText(item.content)
                .setStyle(Notification.BigTextStyle().bigText(item.content).setSummaryText("复习内容"))
                .setCategory(Notification.CATEGORY_REMINDER)
                .setPriority(Notification.PRIORITY_HIGH)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setAutoCancel(true)
                .setContentIntent(contentIntent)
                .build()
            manager.notify(item.id, notification)
        }

    }
}

private data class Settings(
    val enabled: Boolean,
    val windowMode: String,
    val startMinute: Int?,
    val endMinute: Int?,
    val intervalMillis: Long,
    val cooldownMillis: Long,
    val allTopics: Boolean,
    val selectedTopics: Set<Int>,
    val weekdayTopics: Map<Int, Set<Int>>,
)

private data class Runtime(
    val lastEvaluationMillis: Long?,
    val lastEvaluationOutcome: String?,
    val lastDispatchMillis: Long?,
    val lastDispatchItemId: Int?,
    val lastDispatchTopicId: Int?,
)

private data class DispatchReservation(
    val candidate: Item,
    val dispatchedAtMillis: Long,
    val previousTopicLastRemindedAtMillis: Long?,
    val previousRuntime: Runtime,
)

private data class Topic(val intervalMillis: Long, val lastRemindedAtMillis: Long?)

private data class Item(
    val id: Int,
    val content: String,
    val topicId: Int,
    val enabled: Boolean,
    val createdAtMillis: Long,
    val lastShownAtMillis: Long?,
    val reminderCount: Int,
)

private data class Due(val candidate: Item, val atMillis: Long)

private data class Evaluation(val candidate: Item?, val nextAtMillis: Long?)
