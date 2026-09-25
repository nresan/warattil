//
//  PrayerTimes.swift
//  Warattil
//
//  Swift port of WarattilV3/app/src/main/java/com/warattil/app/azan/PrayerTimes.kt
//  Kept byte-for-byte equivalent in behaviour so the iOS app computes the
//  exact same minute-of-day for each prayer as the Android version.
//
//  Implements the standard astronomical algorithm published by praytimes.org,
//  parameterised for the Umm al-Qura method (Saudi Arabia, our global default
//  per the «simple > complete» mandate — one method, no picker in v1).
//
//  Umm al-Qura parameters:
//    • Fajr angle      18.5° below horizon
//    • Sunrise / Sunset 0.833° below horizon (atmospheric refraction + solar radius)
//    • Maghrib         = actual sunset
//    • Isha            = Maghrib + 90 minutes (fixed interval, NOT angle-based)
//    • Asr             = Standard / Shafi'i shadow ratio 1.0
//
//  All trig done in degrees — easier to match the published algorithm.
//  No external dependencies; runs entirely offline.
//

import Foundation

enum Prayer: String, CaseIterable, Codable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    var arabicName: String {
        switch self {
        case .fajr:    return "الفجر"
        case .dhuhr:   return "الظهر"
        case .asr:     return "العصر"
        case .maghrib: return "المغرب"
        case .isha:    return "العشاء"
        }
    }

    /// Stable key for UserDefaults reads/writes — matches the Android
    /// AzanSettings.Mode prefKey convention for documentation parity.
    var prefKey: String { rawValue }

    /// Five prayers in chronological daily order — the same as
    /// Android's PrayerTimes.Prayer.ORDER.  Use this anywhere you need
    /// to iterate prayers in display order.
    static let order: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
}

enum PrayerTimes {

    /// Minutes-since-local-midnight for each of the five daily prayers.
    /// 0 ≤ value < 1440.
    struct Times {
        let fajr:    Int
        let dhuhr:   Int
        let asr:     Int
        let maghrib: Int
        let isha:    Int

        func forPrayer(_ p: Prayer) -> Int {
            switch p {
            case .fajr:    return fajr
            case .dhuhr:   return dhuhr
            case .asr:     return asr
            case .maghrib: return maghrib
            case .isha:    return isha
            }
        }
    }

    /// Which prayer is next, and how many wall-clock minutes until it fires.
    struct NextPrayer {
        let prayer:       Prayer
        let minutesUntil: Int
    }

    // MARK: - Public API ---------------------------------------------------

    /// Compute the five prayer times for a given local date + geographic
    /// position.  Mirrors the Kotlin signature.
    ///
    /// - Parameters:
    ///   - date:      Any DateComponents-resolvable date in the device's
    ///                local timezone — the timezone drives the local-clock
    ///                output (we read it from the supplied Calendar).
    ///   - latitude:  degrees north (positive) / south (negative)
    ///   - longitude: degrees east (positive) / west (negative)
    static func compute(date: Date,
                        timeZone: TimeZone = .current,
                        latitude: Double,
                        longitude: Double) -> Times {
        let tzHours = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        // Julian day for the local noon of the requested date (adjusting by
        // longitude keeps the sun-position correct relative to the location).
        let baseJd  = julianDay(date: date, timeZone: timeZone)
        let jd      = baseJd - longitude / (15.0 * 24.0)
        let (decl, eqt) = sunPosition(jd: jd)

        // Solar noon in local clock time (hours since local midnight).
        let dhuhr = 12.0 + tzHours - longitude / 15.0 - eqt / 60.0

        // Time deltas (hours) from solar noon for each event.
        let fajrDelta   = hourAngle(angleBelowHorizon: 18.5,  lat: latitude, decl: decl)
        let sunsetDelta = hourAngle(angleBelowHorizon: 0.833, lat: latitude, decl: decl)
        let asrDelta    = asrHourAngle(shadowFactor: 1.0,     lat: latitude, decl: decl)

        let fajr    = dhuhr - fajrDelta
        let asr     = dhuhr + asrDelta
        let maghrib = dhuhr + sunsetDelta
        let isha    = maghrib + 1.5   // Umm al-Qura: +90 min after Maghrib

        return Times(
            fajr:    toMinutes(fajr),
            dhuhr:   toMinutes(dhuhr),
            asr:     toMinutes(asr),
            maghrib: toMinutes(maghrib),
            isha:    toMinutes(isha)
        )
    }

    /// Find the next upcoming prayer after [now].  If today's five have all
    /// passed, returns tomorrow's Fajr.  Mirrors Kotlin's nextAfter.
    static func nextAfter(now: Date,
                          timeZone: TimeZone = .current,
                          latitude: Double,
                          longitude: Double) -> NextPrayer {
        let today  = compute(date: now, timeZone: timeZone, latitude: latitude, longitude: longitude)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let parts  = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        for p in Prayer.order {
            let t = today.forPrayer(p)
            if t > nowMin { return NextPrayer(prayer: p, minutesUntil: t - nowMin) }
        }
        // Past Isha — next is tomorrow's Fajr.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let tomorrowFajr = compute(date: tomorrow, timeZone: timeZone, latitude: latitude, longitude: longitude).fajr
        return NextPrayer(prayer: .fajr, minutesUntil: (1440 - nowMin) + tomorrowFajr)
    }

    /// Convert a Times entry's minute-of-day + a base local date into an
    /// absolute Date (wall-clock).  Helper for callers building local
    /// notification triggers — gives them a Date directly without having
    /// to do the Calendar math themselves.
    static func absoluteDate(forMinutesOfDay m: Int,
                             on baseDate: Date,
                             timeZone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: baseDate)
        var build = DateComponents()
        build.year     = comps.year
        build.month    = comps.month
        build.day      = comps.day
        build.hour     = m / 60
        build.minute   = m % 60
        build.second   = 0
        build.timeZone = timeZone
        return cal.date(from: build)!
    }

    // MARK: - Internals ----------------------------------------------------

    /// Convert hours-since-local-midnight into wall-clock minutes [0..1439].
    private static func toMinutes(_ h: Double) -> Int {
        let mins = Int((h * 60.0).rounded())
        return ((mins % 1440) + 1440) % 1440
    }

    private static func julianDay(date: Date, timeZone: TimeZone) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        var y = Double(c.year ?? 2026)
        var m = Double(c.month ?? 1)
        let d = Double(c.day ?? 1)
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(y / 100.0)
        let b = 2.0 - a + floor(a / 4.0)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + d + b - 1524.5
    }

    /// Returns (declination in degrees, equation of time in minutes).
    private static func sunPosition(jd: Double) -> (Double, Double) {
        let d  = jd - 2451545.0
        let g  = fixAngle(357.529 + 0.98560028 * d)
        let q  = fixAngle(280.459 + 0.98564736 * d)
        let l  = fixAngle(q + 1.915 * sinD(g) + 0.020 * sinD(2 * g))
        let e  = 23.439 - 0.00000036 * d
        let ra = atan2D(cosD(e) * sinD(l), cosD(l)) / 15.0
        let decl = asinD(sinD(e) * sinD(l))
        let eqt  = q / 15.0 - fixHour(ra)
        return (decl, eqt * 60.0)
    }

    /// Hour-angle in hours for a sun [angleBelowHorizon] degrees below the horizon.
    private static func hourAngle(angleBelowHorizon: Double, lat: Double, decl: Double) -> Double {
        let num = -sinD(angleBelowHorizon) - sinD(lat) * sinD(decl)
        let den = cosD(lat) * cosD(decl)
        let ratio = min(max(num / den, -1.0), 1.0)
        return acosD(ratio) / 15.0
    }

    /// Hour-angle for Asr: shadow length = object length × [shadowFactor] + noon shadow.
    private static func asrHourAngle(shadowFactor: Double, lat: Double, decl: Double) -> Double {
        let a = -atanD(1.0 / (shadowFactor + tanD(abs(lat - decl))))
        return hourAngle(angleBelowHorizon: a, lat: lat, decl: decl)
    }

    private static func fixAngle(_ a: Double) -> Double {
        let x = a - 360.0 * floor(a / 360.0)
        return x < 0 ? x + 360.0 : x
    }
    private static func fixHour(_ h: Double) -> Double {
        let x = h - 24.0 * floor(h / 24.0)
        return x < 0 ? x + 24.0 : x
    }

    // Degree-based trig helpers (the algorithm is most naturally expressed
    // in degrees; converting to radians inline would obscure the math).
    private static func sinD (_ d: Double) -> Double { sin(d * .pi / 180.0) }
    private static func cosD (_ d: Double) -> Double { cos(d * .pi / 180.0) }
    private static func tanD (_ d: Double) -> Double { tan(d * .pi / 180.0) }
    private static func asinD(_ d: Double) -> Double { asin(d) * 180.0 / .pi }
    private static func acosD(_ d: Double) -> Double { acos(d) * 180.0 / .pi }
    private static func atanD(_ d: Double) -> Double { atan(d) * 180.0 / .pi }
    private static func atan2D(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180.0 / .pi }
}
