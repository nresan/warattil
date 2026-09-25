package com.warattil.app.azan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// =============================================================================
// AzanBootReceiver — re-arms the five daily prayer alarms after the device
// reboots.
//
// AlarmManager alarms do NOT survive a reboot.  Without this receiver the
// prayer reminders would silently stop until the user reopens the app.
//
// We listen for BOOT_COMPLETED + the locked-boot variant (Android 7+
// direct-boot phones fire LOCKED_BOOT_COMPLETED before the user unlocks).
// In both cases we just call scheduleAll, which is a no-op if the user
// hasn't enabled the feature yet.
// =============================================================================

class AzanBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" -> {
                AzanScheduler.scheduleAll(context)
            }
        }
    }
}
