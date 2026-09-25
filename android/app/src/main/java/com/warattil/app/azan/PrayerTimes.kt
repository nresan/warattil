package com.warattil.app.azan

import java.util.Calendar
import kotlin.math.*

// =============================================================================
// PrayerTimes — local prayer-time calculation.
//
// Implements the standard astronomical algorithm published by praytimes.org,
// parameterised for the Umm al-Qura method (Saudi Arabia, our global default
// per the «simple > complete» mandate — one method, no picker in v1).
//
// Umm al-Qura parameters:
//   • Fajr angle      18.5° below horizon
//   • Sunrise / Sunset 0.833° below horizon (atmospheric refraction + solar radius)
//   • Maghrib         = actual sunset
//   • Isha            = Maghrib + 90 minutes (fixed interval, NOT angle-based)
//   • Asr             = Standard / Shafi'i shadow ratio 1.0
//
// All trig is done in degrees (the algorithm is most naturally expressed
// that way; converting to radians inline would obscure the math).
//
// No external dependencies — runs entirely offline.
// =============================================================================

object PrayerTimes {

    enum class Prayer(val arabicName: String, val prefKey: String) {
        FAJR   ("الفجر",  "fajr"),
        DHUHR  ("الظهر",  "dhuhr"),
        ASR    ("العصر",  "asr"),
        MAGHRIB("المغرب", "maghrib"),
        ISHA   ("العشاء", "isha");

        companion object { val ORDER = values().toList() }
    }

    /** Minutes since midnight (local time) for each prayer. */
    data class Times(
        val fajr   : Int,
        val dhuhr  : Int,
        val asr    : Int,
        val maghrib: Int,
        val isha   : Int
    ) {
        fun forPrayer(p: Prayer): Int = when (p) {
            Prayer.FAJR    -> fajr
            Prayer.DHUHR   -> dhuhr
            Prayer.ASR     -> asr
            Prayer.MAGHRIB -> maghrib
            Prayer.ISHA    -> isha
        }
    }

    /**
     * Compute the five prayer times for a given local date + geographic position.
     *
     * @param date      Calendar set to any time on the desired *local* day; the
     *                  timezone of this Calendar drives the local-clock output.
     * @param latitude  degrees north (positive) / south (negative)
     * @param longitude degrees east (positive) / west (negative)
     */
    fun compute(date: Calendar, latitude: Double, longitude: Double): Times {
        val tzHours   = date.timeZone.getOffset(date.timeInMillis) / 3_600_000.0
        // Julian day for the local noon of the requested date (adjusting by
        // longitude keeps the sun-position correct relative to the location).
        val baseJd    = julianDay(date)
        val jd        = baseJd - longitude / (15.0 * 24.0)
        val (decl, eqt) = sunPosition(jd)

        // Solar noon in local clock time (hours since local midnight).
        val dhuhr = 12.0 + tzHours - longitude / 15.0 - eqt / 60.0

        // Time deltas (hours) from solar noon for each event.
        val fajrDelta    = hourAngle(18.5,  latitude, decl)
        val sunsetDelta  = hourAngle(0.833, latitude, decl)   // for Maghrib
        val asrDelta     = asrHourAngle(1.0, latitude, decl)  // Shafi'i

        val fajr    = dhuhr - fajrDelta
        val asr     = dhuhr + asrDelta
        val maghrib = dhuhr + sunsetDelta
        val isha    = maghrib + 1.5   // Umm al-Qura: +90 min after Maghrib

        return Times(
            fajr    = toMinutes(fajr),
            dhuhr   = toMinutes(dhuhr),
            asr     = toMinutes(asr),
            maghrib = toMinutes(maghrib),
            isha    = toMinutes(isha)
        )
    }

    /** Convert hours-since-local-midnight into wall-clock minutes [0..1439]. */
    private fun toMinutes(h: Double): Int {
        val mins = (h * 60.0).roundToInt()
        return ((mins % 1440) + 1440) % 1440
    }

    // ── Next-prayer lookup (used by the widget + future surfaces) ────────────

    /** Which prayer is next, and how many wall-clock minutes until it fires. */
    data class NextPrayer(val prayer: Prayer, val minutesUntil: Int)

    /**
     * Find the next upcoming prayer after [now]. If all of today's prayers
     * have already passed, returns tomorrow's Fajr.
     */
    fun nextAfter(now: Calendar, latitude: Double, longitude: Double): NextPrayer {
        val today  = compute(now, latitude, longitude)
        val nowMin = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        for (p in Prayer.ORDER) {
            val t = today.forPrayer(p)
            if (t > nowMin) return NextPrayer(p, t - nowMin)
        }
        // Past Isha — next is tomorrow's Fajr.
        val tomorrow = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        val tomorrowFajr = compute(tomorrow, latitude, longitude).fajr
        return NextPrayer(Prayer.FAJR, (1440 - nowMin) + tomorrowFajr)
    }

    /**
     * One upcoming prayer entry with absolute wall-clock millis and the
     * minute-of-day on its scheduled day.  Used by the prayer-focused
     * widget which shows the next two upcoming prayers side-by-side with
     * a live-ticking Chronometer countdown to each.
     *
     *  fireTimeMillis        = absolute System.currentTimeMillis() value
     *                          when the prayer fires — feed directly into
     *                          Chronometer base via SystemClock translation.
     *  fireMinuteOfDay       = minute-of-day on the prayer's local day
     *                          (0..1439) — for the "العشاء ٧:٥٢" label.
     */
    data class UpcomingPrayer(
        val prayer        : Prayer,
        val fireTimeMillis: Long,
        val fireMinuteOfDay: Int
    )

    /**
     * Return the next two upcoming prayers after [now], spanning today and
     * tomorrow as needed.  Always returns exactly two — if today has only
     * one prayer left, the second is tomorrow's Fajr; if today has all five
     * passed, both are tomorrow's prayers.
     *
     * Used by the prayer-focused home-screen widget (2026-05-19 redesign).
     */
    fun nextTwoAfter(now: Calendar, latitude: Double, longitude: Double): Pair<UpcomingPrayer, UpcomingPrayer> {
        // Local midnight as absolute millis — base for converting
        // minute-of-day → wall-clock millis on today's and tomorrow's days.
        val todayMidnight = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE,      0)
            set(Calendar.SECOND,      0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val tomorrowMidnight = todayMidnight + 24L * 60 * 60 * 1000

        val todayTimes = compute(now, latitude, longitude)
        val tomorrowCal = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        val tomorrowTimes = compute(tomorrowCal, latitude, longitude)

        val nowMs = now.timeInMillis

        // Build a chronological list: today's five + tomorrow's five (10 entries
        // total), keep only those still in the future.  Take the first two.
        val candidates = mutableListOf<UpcomingPrayer>()
        for (p in Prayer.ORDER) {
            val minOfDay = todayTimes.forPrayer(p)
            candidates.add(UpcomingPrayer(p, todayMidnight + minOfDay * 60_000L, minOfDay))
        }
        for (p in Prayer.ORDER) {
            val minOfDay = tomorrowTimes.forPrayer(p)
            candidates.add(UpcomingPrayer(p, tomorrowMidnight + minOfDay * 60_000L, minOfDay))
        }
        val upcoming = candidates.filter { it.fireTimeMillis > nowMs }
        // Guaranteed to have at least 6 entries (5 of tomorrow + ≥1 of today).
        return Pair(upcoming[0], upcoming[1])
    }

    // ── Astronomy primitives ─────────────────────────────────────────────────

    private fun julianDay(cal: Calendar): Double {
        val year  = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1
        val day   = cal.get(Calendar.DAY_OF_MONTH)
        var y = year
        var m = month
        if (m <= 2) { y -= 1; m += 12 }
        val a = floor(y / 100.0)
        val b = 2 - a + floor(a / 4.0)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + day + b - 1524.5
    }

    /** Returns (declination in degrees, equation of time in minutes). */
    private fun sunPosition(jd: Double): Pair<Double, Double> {
        val d  = jd - 2451545.0
        val g  = fixAngle(357.529 + 0.98560028 * d)
        val q  = fixAngle(280.459 + 0.98564736 * d)
        val l  = fixAngle(q + 1.915 * sinD(g) + 0.020 * sinD(2 * g))
        val e  = 23.439 - 0.00000036 * d
        val ra = atan2D(cosD(e) * sinD(l), cosD(l)) / 15.0
        val decl = asinD(sinD(e) * sinD(l))
        val eqt  = q / 15.0 - fixHour(ra)
        return Pair(decl, eqt * 60.0)
    }

    /** Hour-angle in hours for a sun [angle] degrees below the horizon. */
    private fun hourAngle(angleBelowHorizon: Double, lat: Double, decl: Double): Double {
        val num = -sinD(angleBelowHorizon) - sinD(lat) * sinD(decl)
        val den = cosD(lat) * cosD(decl)
        val ratio = (num / den).coerceIn(-1.0, 1.0)
        return acosD(ratio) / 15.0
    }

    /** Hour-angle for Asr: shadow length = object length × [shadowFactor] + noon shadow. */
    private fun asrHourAngle(shadowFactor: Double, lat: Double, decl: Double): Double {
        val a = -atanD(1.0 / (shadowFactor + tanD(abs(lat - decl))))
        return hourAngle(a, lat, decl)
    }

    private fun fixAngle(a: Double): Double {
        val x = a - 360.0 * floor(a / 360.0)
        return if (x < 0) x + 360.0 else x
    }

    private fun fixHour(h: Double): Double {
        val x = h - 24.0 * floor(h / 24.0)
        return if (x < 0) x + 24.0 else x
    }

    // ── Degree-based trig helpers ────────────────────────────────────────────
    private fun sinD (d: Double) = sin(d * PI / 180.0)
    private fun cosD (d: Double) = cos(d * PI / 180.0)
    private fun tanD (d: Double) = tan(d * PI / 180.0)
    private fun asinD(d: Double) = asin(d) * 180.0 / PI
    private fun acosD(d: Double) = acos(d) * 180.0 / PI
    private fun atanD(d: Double) = atan(d) * 180.0 / PI
    private fun atan2D(y: Double, x: Double) = atan2(y, x) * 180.0 / PI
}
