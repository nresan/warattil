package com.warattil.app.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AudioFile
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.warattil.app.azan.AzanScheduler
import com.warattil.app.azan.AzanSettings
import com.warattil.app.azan.PrayerTimes
import com.warattil.app.widget.WarattilWidgetReceiver
import java.util.Calendar

// =============================================================================
// AzanSettingsSheet — «أوقات الصلاة»
//
// Three logical sections, scrolled vertically inside a modal bottom sheet:
//
//   1. Master toggle + location status
//      — One-tap enable / disable; shows the captured location label so
//        the user knows the times are anchored to *their* city.
//
//   2. Audio file slots
//      — Two upload affordances (full + short).  Each opens SAF
//        ACTION_OPEN_DOCUMENT for audio/* and persists the URI grant so
//        the file survives reboot.  Empty slot = "لم يتم التحميل".
//
//   3. Per-prayer mode picker
//      — One row per prayer (Fajr / Dhuhr / Asr / Maghrib / Isha).
//        Each row offers three radio choices: full azan, short azan,
//        notification-only.  Selecting "full" or "short" while the
//        corresponding audio slot is empty silently degrades to
//        notification-only at fire time (handled in AzanSettings.resolveAudioFor).
//
// Settings changes write through to SharedPreferences immediately and
// re-schedule the AlarmManager queue so the live state always matches
// what the user sees.
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AzanSettingsSheet(
    font     : QuranFontInfo,
    theme    : ThemeColors,
    onDismiss: () -> Unit
) {
    val ctx = LocalContext.current
    val haveLocation = remember { mutableStateOf(AzanSettings.getLocation(ctx) != null) }
    val locationLabel = remember { mutableStateOf(AzanSettings.locationLabel(ctx)) }
    val enabled = remember { mutableStateOf(AzanSettings.isEnabled(ctx)) }

    // Audio slot state — refreshed on each SAF return
    val fullName  = remember { mutableStateOf(AzanSettings.audioFullName(ctx)) }
    val shortName = remember { mutableStateOf(AzanSettings.audioShortName(ctx)) }

    // Per-prayer mode state
    val modes = remember {
        mutableStateOf(PrayerTimes.Prayer.ORDER.associateWith { AzanSettings.getMode(ctx, it) })
    }

    // ── SAF file pickers (one per slot) ──────────────────────────────────────
    val pickFull = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            // Persist the URI permission so the file remains readable after reboot
            try {
                ctx.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { /* OK — fallback to non-persistable */ }
            val name = displayName(ctx, uri)
            AzanSettings.setAudioFull(ctx, uri.toString(), name)
            fullName.value = name
        }
    }

    val pickShort = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                ctx.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { }
            val name = displayName(ctx, uri)
            AzanSettings.setAudioShort(ctx, uri.toString(), name)
            shortName.value = name
        }
    }

    // ── Location permission launcher ─────────────────────────────────────────
    val locationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { grants ->
        val granted = grants[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                      grants[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (granted) {
            captureLocation(ctx)?.let { (lat, lng) ->
                AzanSettings.setLocation(ctx, lat, lng, label = "")
                haveLocation.value = true
                locationLabel.value = "${"%.3f".format(lat)}، ${"%.3f".format(lng)}"
                // If feature is enabled, refresh the alarm queue now that
                // we finally have a location to compute against.
                if (enabled.value) AzanScheduler.scheduleAll(ctx)
                // Widget can now compute "next prayer in N minutes" — refresh.
                WarattilWidgetReceiver.updateAll(ctx)
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = theme.background) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 680.dp)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 22.dp, vertical = 12.dp)
            ) {
                SectionHeading("أوقات الصلاة", font, theme)
                GoldHairline(theme)
                Spacer(Modifier.height(14.dp))

                Text(
                    text       = "تذكير هادئ بالصلوات الخمس — لتقترن قراءتك للقرآن بإقامة الصلاة في وقتها.",
                    color      = theme.text.copy(alpha = 0.75f),
                    fontSize   = 13.sp,
                    fontFamily = FontFamily.Default,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth(),
                    style      = TextStyle(textDirection = TextDirection.Rtl, lineHeight = 22.sp)
                )
                Spacer(Modifier.height(18.dp))

                // ── Master toggle ────────────────────────────────────────────
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(theme.bannerBg, RoundedCornerShape(10.dp))
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Notifications, null,
                        tint = theme.gold, modifier = Modifier.size(22.dp)
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        text       = "تفعيل تذكير الصلاة",
                        color      = theme.text,
                        fontSize   = 16.sp,
                        fontFamily = font.family,
                        fontWeight = FontWeight.Medium,
                        modifier   = Modifier.weight(1f)
                    )
                    Switch(
                        checked = enabled.value,
                        onCheckedChange = { now ->
                            enabled.value = now
                            AzanSettings.setEnabled(ctx, now)
                            if (now) {
                                if (haveLocation.value) AzanScheduler.scheduleAll(ctx)
                            } else {
                                AzanScheduler.cancelAll(ctx)
                            }
                            // Show / hide the countdown line on the home-screen widget.
                            WarattilWidgetReceiver.updateAll(ctx)
                        },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor  = theme.background,
                            checkedTrackColor  = theme.accent,
                            uncheckedThumbColor= theme.text.copy(alpha = 0.4f),
                            uncheckedTrackColor= theme.bannerBg
                        )
                    )
                }

                Spacer(Modifier.height(12.dp))

                // ── Location row ─────────────────────────────────────────────
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(1.dp, theme.divider, RoundedCornerShape(10.dp))
                        .clickable {
                            locationPermissionLauncher.launch(arrayOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION
                            ))
                        }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.LocationOn, null,
                        tint = if (haveLocation.value) theme.accent else theme.text.copy(alpha = 0.4f),
                        modifier = Modifier.size(22.dp)
                    )
                    Spacer(Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text       = if (haveLocation.value) "تم تحديد موقعك" else "حدِّد موقعك",
                            color      = theme.text,
                            fontSize   = 15.sp,
                            fontFamily = font.family,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text       = if (haveLocation.value)
                                            "نحسب أوقات الصلاة وفقًا لإحداثياتك (${locationLabel.value})"
                                         else
                                            "نحتاج إذن الموقع لحساب أوقات الصلاة في مدينتك",
                            color      = theme.text.copy(alpha = 0.6f),
                            fontSize   = 12.sp,
                            fontFamily = FontFamily.Default,
                            style      = TextStyle(textDirection = TextDirection.Rtl, lineHeight = 18.sp)
                        )
                    }
                }

                Spacer(Modifier.height(22.dp))

                // ── Audio slots intro ────────────────────────────────────────
                SectionHeading("ملف الأذان", font, theme)
                Spacer(Modifier.height(8.dp))
                Text(
                    text       = "لسماع الأذان بصوت مؤذنك المفضّل، حمّل الملف الصوتي بأيّ صيغة متوفّرة لديك.",
                    color      = theme.text.copy(alpha = 0.75f),
                    fontSize   = 13.sp,
                    fontFamily = FontFamily.Default,
                    style      = TextStyle(textDirection = TextDirection.Rtl, lineHeight = 22.sp)
                )
                Spacer(Modifier.height(12.dp))

                AudioSlotRow(
                    label    = "الأذان الكامل",
                    helper   = "حمّل ملف الأذان الكامل من هنا",
                    fileName = fullName.value,
                    theme    = theme,
                    font     = font,
                    onPick   = { pickFull.launch(arrayOf("audio/*")) },
                    onClear  = {
                        AzanSettings.setAudioFull(ctx, null, "")
                        fullName.value = ""
                    }
                )
                Spacer(Modifier.height(10.dp))
                AudioSlotRow(
                    label    = "الأذان المختصر",
                    helper   = "حمّل ملف الأذان المختصر من هنا",
                    fileName = shortName.value,
                    theme    = theme,
                    font     = font,
                    onPick   = { pickShort.launch(arrayOf("audio/*")) },
                    onClear  = {
                        AzanSettings.setAudioShort(ctx, null, "")
                        shortName.value = ""
                    }
                )

                Spacer(Modifier.height(22.dp))

                // ── Per-prayer mode ──────────────────────────────────────────
                SectionHeading("اختر لكل صلاة", font, theme)
                Spacer(Modifier.height(8.dp))
                Text(
                    text       = "لكلّ صلاة من الصلوات الخمس اختر: الأذان الكامل، الأذان المختصر، أو تنبيهًا على الشاشة مع الاهتزاز.",
                    color      = theme.text.copy(alpha = 0.75f),
                    fontSize   = 13.sp,
                    fontFamily = FontFamily.Default,
                    style      = TextStyle(textDirection = TextDirection.Rtl, lineHeight = 22.sp)
                )
                Spacer(Modifier.height(12.dp))

                PrayerTimes.Prayer.ORDER.forEach { prayer ->
                    PerPrayerRow(
                        prayer  = prayer,
                        current = modes.value[prayer] ?: AzanSettings.Mode.NOTIFICATION_ONLY,
                        font    = font,
                        theme   = theme,
                        onPick  = { newMode ->
                            modes.value = modes.value.toMutableMap().also { it[prayer] = newMode }
                            AzanSettings.setMode(ctx, prayer, newMode)
                            // Mode change doesn't shift fire times, but rescheduling
                            // is cheap and ensures the alarm queue + settings stay
                            // strictly consistent if a side-effect rule changes later.
                            if (enabled.value && haveLocation.value) {
                                AzanScheduler.scheduleAll(ctx)
                            }
                        }
                    )
                    Spacer(Modifier.height(8.dp))
                }

                Spacer(Modifier.height(20.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(10.dp))

                Text(
                    text       = "يبقى التذكير على الشاشة هادئًا حتى تختار سماع الأذان بصوت مؤذنك.",
                    color      = theme.text.copy(alpha = 0.5f),
                    fontSize   = 11.sp,
                    fontFamily = FontFamily.Default,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth(),
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // If the sheet opens and we already have a location but haven't started
    // the alarm queue (e.g. user re-enabled after granting), make sure the
    // scheduler is current.
    LaunchedEffect(Unit) {
        if (enabled.value && haveLocation.value) AzanScheduler.scheduleAll(ctx)
    }
}

// =============================================================================
// Sub-rows
// =============================================================================

@Composable
private fun AudioSlotRow(
    label   : String,
    helper  : String,
    fileName: String,
    theme   : ThemeColors,
    font    : QuranFontInfo,
    onPick  : () -> Unit,
    onClear : () -> Unit
) {
    val hasFile = fileName.isNotBlank()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, theme.divider, RoundedCornerShape(10.dp))
            .clickable { onPick() }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            Icons.Default.AudioFile, null,
            tint = if (hasFile) theme.accent else theme.text.copy(alpha = 0.5f),
            modifier = Modifier.size(22.dp)
        )
        Spacer(Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text       = label,
                color      = theme.text,
                fontSize   = 15.sp,
                fontFamily = font.family,
                fontWeight = FontWeight.Medium
            )
            Text(
                text       = if (hasFile) fileName else helper,
                color      = if (hasFile) theme.accent.copy(alpha = 0.85f)
                             else         theme.text.copy(alpha = 0.6f),
                fontSize   = 12.sp,
                fontFamily = FontFamily.Default,
                style      = TextStyle(textDirection = TextDirection.Rtl, lineHeight = 18.sp)
            )
        }
        if (hasFile) {
            Text(
                text       = "إزالة",
                color      = theme.text.copy(alpha = 0.6f),
                fontSize   = 12.sp,
                fontFamily = FontFamily.Default,
                modifier   = Modifier.clickable { onClear() }
            )
        }
    }
}

@Composable
private fun PerPrayerRow(
    prayer : PrayerTimes.Prayer,
    current: AzanSettings.Mode,
    font   : QuranFontInfo,
    theme  : ThemeColors,
    onPick : (AzanSettings.Mode) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, theme.divider, RoundedCornerShape(10.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Text(
            text       = prayer.arabicName,
            color      = theme.accent,
            fontSize   = 17.sp,
            fontFamily = font.family,
            fontWeight = FontWeight.Medium,
            textAlign  = TextAlign.End,
            modifier   = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(6.dp))

        ModeRadio(
            label   = "الأذان الكامل",
            icon    = Icons.Default.VolumeUp,
            selected= current == AzanSettings.Mode.FULL,
            font    = font, theme = theme,
            onClick = { onPick(AzanSettings.Mode.FULL) }
        )
        ModeRadio(
            label   = "الأذان المختصر",
            icon    = Icons.Default.VolumeUp,
            selected= current == AzanSettings.Mode.SHORT,
            font    = font, theme = theme,
            onClick = { onPick(AzanSettings.Mode.SHORT) }
        )
        ModeRadio(
            label   = "تنبيه على الشاشة مع الاهتزاز",
            icon    = Icons.Default.Notifications,
            selected= current == AzanSettings.Mode.NOTIFICATION_ONLY,
            font    = font, theme = theme,
            onClick = { onPick(AzanSettings.Mode.NOTIFICATION_ONLY) }
        )
    }
}

@Composable
private fun ModeRadio(
    label   : String,
    icon    : androidx.compose.ui.graphics.vector.ImageVector,
    selected: Boolean,
    font    : QuranFontInfo,
    theme   : ThemeColors,
    onClick : () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = if (selected) Icons.Default.RadioButtonChecked
                          else          Icons.Default.RadioButtonUnchecked,
            contentDescription = null,
            tint     = if (selected) theme.accent else theme.text.copy(alpha = 0.4f),
            modifier = Modifier.size(18.dp)
        )
        Spacer(Modifier.width(8.dp))
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (selected) theme.gold else theme.text.copy(alpha = 0.45f),
            modifier = Modifier.size(16.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            text       = label,
            color      = if (selected) theme.text else theme.text.copy(alpha = 0.7f),
            fontSize   = 14.sp,
            fontFamily = font.family
        )
    }
}

// =============================================================================
// Helpers
// =============================================================================

private fun displayName(ctx: Context, uri: Uri): String {
    return try {
        ctx.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else "ملف صوتي"
        } ?: "ملف صوتي"
    } catch (_: Throwable) { "ملف صوتي" }
}

private fun captureLocation(ctx: Context): Pair<Double, Double>? {
    val granted = ContextCompat.checkSelfPermission(
        ctx, Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED ||
    ContextCompat.checkSelfPermission(
        ctx, Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
    if (!granted) return null

    val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
    val providers = lm.getProviders(true)
    for (provider in providers) {
        try {
            @Suppress("MissingPermission")
            val loc = lm.getLastKnownLocation(provider)
            if (loc != null) return Pair(loc.latitude, loc.longitude)
        } catch (_: SecurityException) { /* try next provider */ }
    }
    return null
}
