package com.warattil.app.azan

import android.content.Context
import androidx.core.content.edit

// =============================================================================
// AzanSettings — SharedPreferences-backed model for the prayer-reminder feature.
//
// Stores:
//   • master on/off
//   • cached location (lat / lng / human-readable label)
//   • two optional audio file URIs (full + short azan) the user uploaded via SAF
//   • per-prayer mode (FULL / SHORT / NOTIFICATION_ONLY)
//
// Persistence rationale: simple key-value, no schema migration overhead,
// matches the existing app prefs file ("warattil_prefs") used by Hifz and
// the widget.  No Room cost for ~10 fields.
// =============================================================================

object AzanSettings {

    /** Per-prayer mode the user picked for a given prayer time. */
    enum class Mode(val pref: String, val label: String) {
        FULL              ("FULL",              "الأذان الكامل"),
        SHORT             ("SHORT",             "الأذان المختصر"),
        NOTIFICATION_ONLY ("NOTIFICATION_ONLY", "تنبيه على الشاشة مع الاهتزاز");

        companion object {
            fun fromPref(s: String?): Mode = values().firstOrNull { it.pref == s } ?: NOTIFICATION_ONLY
        }
    }

    // SharedPreferences keys
    private const val FILE              = "warattil_prefs"
    private const val K_ENABLED         = "azan_enabled"
    private const val K_LAT             = "azan_lat"
    private const val K_LNG             = "azan_lng"
    private const val K_LOC_LABEL       = "azan_location_label"
    private const val K_AUDIO_FULL_URI  = "azan_audio_full_uri"
    private const val K_AUDIO_SHORT_URI = "azan_audio_short_uri"
    private const val K_AUDIO_FULL_NAME = "azan_audio_full_name"
    private const val K_AUDIO_SHORT_NAME= "azan_audio_short_name"
    private fun modeKey(p: PrayerTimes.Prayer) = "azan_mode_${p.prefKey}"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    // ── Master toggle ────────────────────────────────────────────────────────
    fun isEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean(K_ENABLED, false)
    fun setEnabled(ctx: Context, enabled: Boolean) {
        prefs(ctx).edit { putBoolean(K_ENABLED, enabled) }
    }

    // ── Location ─────────────────────────────────────────────────────────────
    /** Returns Pair(lat, lng) if captured, or null if the user hasn't granted yet. */
    fun getLocation(ctx: Context): Pair<Double, Double>? {
        val p = prefs(ctx)
        if (!p.contains(K_LAT) || !p.contains(K_LNG)) return null
        return Pair(
            p.getFloat(K_LAT, 0f).toDouble(),
            p.getFloat(K_LNG, 0f).toDouble()
        )
    }

    fun setLocation(ctx: Context, lat: Double, lng: Double, label: String = "") {
        prefs(ctx).edit {
            putFloat(K_LAT, lat.toFloat())
            putFloat(K_LNG, lng.toFloat())
            if (label.isNotEmpty()) putString(K_LOC_LABEL, label)
        }
    }

    fun locationLabel(ctx: Context): String = prefs(ctx).getString(K_LOC_LABEL, "") ?: ""

    // ── Audio URIs (persistable SAF URIs) ───────────────────────────────────
    fun audioFullUri(ctx: Context):   String? = prefs(ctx).getString(K_AUDIO_FULL_URI,  null)
    fun audioShortUri(ctx: Context):  String? = prefs(ctx).getString(K_AUDIO_SHORT_URI, null)
    fun audioFullName(ctx: Context):  String  = prefs(ctx).getString(K_AUDIO_FULL_NAME,  "") ?: ""
    fun audioShortName(ctx: Context): String  = prefs(ctx).getString(K_AUDIO_SHORT_NAME, "") ?: ""

    fun setAudioFull (ctx: Context, uri: String?, fileName: String) {
        prefs(ctx).edit {
            if (uri == null) {
                remove(K_AUDIO_FULL_URI); remove(K_AUDIO_FULL_NAME)
            } else {
                putString(K_AUDIO_FULL_URI, uri); putString(K_AUDIO_FULL_NAME, fileName)
            }
        }
    }

    fun setAudioShort(ctx: Context, uri: String?, fileName: String) {
        prefs(ctx).edit {
            if (uri == null) {
                remove(K_AUDIO_SHORT_URI); remove(K_AUDIO_SHORT_NAME)
            } else {
                putString(K_AUDIO_SHORT_URI, uri); putString(K_AUDIO_SHORT_NAME, fileName)
            }
        }
    }

    // ── Per-prayer mode ──────────────────────────────────────────────────────
    fun getMode(ctx: Context, p: PrayerTimes.Prayer): Mode =
        Mode.fromPref(prefs(ctx).getString(modeKey(p), Mode.NOTIFICATION_ONLY.pref))

    fun setMode(ctx: Context, p: PrayerTimes.Prayer, mode: Mode) {
        prefs(ctx).edit { putString(modeKey(p), mode.pref) }
    }

    /**
     * Resolve the audio URI to play for [p] given current settings.
     * Returns null when:
     *   • the user picked NOTIFICATION_ONLY, OR
     *   • the user picked FULL/SHORT but hasn't uploaded the corresponding file.
     * The receiver treats null as "show notification only, no audio."
     */
    fun resolveAudioFor(ctx: Context, p: PrayerTimes.Prayer): String? = when (getMode(ctx, p)) {
        Mode.FULL              -> audioFullUri(ctx)
        Mode.SHORT             -> audioShortUri(ctx)
        Mode.NOTIFICATION_ONLY -> null
    }
}
