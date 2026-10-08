package com.wly112488.android_process_state;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;

public class ActivityVisibilityTest {
    @Before
    public void resetVisibility() {
        ActivityVisibility.INSTANCE.onActivityPaused();
    }

    @Test
    public void activityIsNotVisibleUntilResumed() {
        assertFalse(ActivityVisibility.INSTANCE.isActivityResumed());

        ActivityVisibility.INSTANCE.onActivityResumed();

        assertTrue(ActivityVisibility.INSTANCE.isActivityResumed());
    }

    @Test
    public void pausedActivityIsNotVisibleToBackgroundReminder() {
        ActivityVisibility.INSTANCE.onActivityResumed();

        ActivityVisibility.INSTANCE.onActivityPaused();

        assertFalse(ActivityVisibility.INSTANCE.isActivityResumed());
    }
}
