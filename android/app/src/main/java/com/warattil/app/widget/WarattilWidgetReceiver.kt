package com.warattil.app.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

// =============================================================================
// WarattilWidgetReceiver — bridges Android widget lifecycle to Glance
// =============================================================================

class WarattilWidgetReceiver : GlanceAppWidgetReceiver() {

    override val glanceAppWidget: GlanceAppWidget = WarattilWidget()

    companion object {
        /**
         * Trigger a re-render of all placed widget instances.
         * Call whenever SharedPreferences widget data changes (e.g. on page swipe).
         */
        fun updateAll(context: Context) {
            MainScope().launch {
                val manager = GlanceAppWidgetManager(context)
                manager.getGlanceIds(WarattilWidget::class.java).forEach { id ->
                    WarattilWidget().update(context, id)
                }
            }
        }
    }
}
