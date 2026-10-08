package com.wly112488.android_process_state

/** Tracks whether the app's foreground Activity is currently resumed. */
object ActivityVisibility {
    @Volatile
    private var activityResumed = false

    fun onActivityResumed() {
        activityResumed = true
    }

    fun onActivityPaused() {
        activityResumed = false
    }

    fun isActivityResumed(): Boolean = activityResumed
}
