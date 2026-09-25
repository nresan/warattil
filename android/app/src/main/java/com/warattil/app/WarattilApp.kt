package com.warattil.app

import android.app.Application
import com.warattil.app.data.MetadataParser
import com.warattil.app.data.QuranRepository

class WarattilApp : Application() {
    override fun onCreate() {
        super.onCreate()
        MetadataParser.load(this)
        // Register notification channels at app start so the OS knows about
        // them before any worker / receiver tries to post.  Idempotent —
        // safe to call on every cold start.
        NotificationHelper.createChannels(this)
    }

    val repository: QuranRepository by lazy { QuranRepository(this) }
}
