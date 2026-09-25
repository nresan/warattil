package com.warattil.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import com.warattil.app.core.WarattilConstants
import com.warattil.app.ui.MushaFScreen
import com.warattil.app.ui.MushaFViewModel
import com.warattil.app.ui.WarattilSplashScreen
import kotlinx.coroutines.delay
import com.warattil.app.widget.WarattilWidgetReceiver

class MainActivity : ComponentActivity() {

    private val viewModel: MushaFViewModel by viewModels {
        MushaFViewModel.Factory(application, (application as WarattilApp).repository)
    }

    // Android 13+ notification permission launcher
    private val notifPermLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* granted or denied — workers are already scheduled; notifications degrade silently */ }

    // ── In-app update wiring ─────────────────────────────────────────────────
    // Play's Flexible update flow:
    //   1. appUpdateManager.appUpdateInfo → Task<AppUpdateInfo>
    //   2. if UPDATE_AVAILABLE && FLEXIBLE allowed → startUpdateFlowForResult
    //   3. listener fires InstallStatus.DOWNLOADED → we flip updateReadyState
    //   4. user taps «إعادة التشغيل الآن» on the banner → completeUpdate()
    //      reinstalls with zero downtime beyond the restart.
    //
    // Why Flexible (not Immediate): Flexible lets the download happen in the
    // background while the reader keeps reading — a "do not interrupt mid-
    // ayah" UX choice. Immediate forces a blocking full-screen dialog up
    // front, which contradicts the ajr-first tone of the app. Future shift
    // to Immediate would be appropriate for an emergency / data-correctness
    // release; this is the default for ordinary version bumps.
    //
    // Why this exists at all: the Play Store client caches the "updates
    // available" list for ~24 h, so users routinely miss new releases for
    // a full day (see: 2.2.0 shipped and Nasser's own device never showed
    // the badge). In-app update bypasses the cache entirely — the check
    // runs on app launch against Play's live backend.
    private lateinit var appUpdateManager: AppUpdateManager

    private val updateReadyState = mutableStateOf(false)

    private val updateListener = InstallStateUpdatedListener { state ->
        if (state.installStatus() == InstallStatus.DOWNLOADED) {
            updateReadyState.value = true
        }
    }

    // Launcher for the Play-provided update consent intent sender. We don't
    // react to the result beyond Play's own handling — the real signal is
    // the InstallStateUpdatedListener registered above, which fires when
    // the download completes regardless of whether the activity is in
    // the foreground.
    private val updateLauncher: ActivityResultLauncher<IntentSenderRequest> =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) {
            /* no-op — DOWNLOADED state arrives via the listener above */
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        // ══════════════════════════════════════════════════════════════════════
        // ⚠️  SPLASH SCREEN — WARATTIL TRADEMARK  ⚠️  DO NOT EDIT CASUALLY
        // ══════════════════════════════════════════════════════════════════════
        //
        // Two-stage splash, mirroring iOS (WarattilApp.swift):
        //
        //   STAGE 1 — System SplashScreen (cold-start bridge, INVISIBLE)
        //     Shown by the OS while the app process boots. Theme is
        //     Theme.App.Starting in res/values/themes.xml — cream
        //     background with an EXPLICITLY invisible icon
        //     (splash_icon_invisible.xml, a solid-cream 288 dp vector)
        //     and icon-background bubble pinned to cream too. Result:
        //     a cream canvas with no visible content — the user sees
        //     nothing branded during cold start.
        //
        //     Why invisible rather than "just omit the icon": on
        //     Android 12+ omitting `windowSplashScreenAnimatedIcon`
        //     causes the platform to fall back to the LAUNCHER icon
        //     with its default adaptive-icon treatment (white disc +
        //     shrunken foreground), which Nasser reported as yet
        //     another "old intro" on 2026-04-22 round 6. The only way
        //     to truly suppress the splash icon is to supply a drawable
        //     that matches the background color.
        //
        //     We do NOT hold this stage with setKeepOnScreenCondition;
        //     it dismisses the instant Compose's first frame paints.
        //     We also strip the default 200 ms exit fade via
        //     setOnExitAnimationListener — any cross-fade between a
        //     blank cream screen and the Compose splash would be a
        //     pointless flicker.
        //
        //   STAGE 2 — WarattilSplashScreen (Compose trademark)
        //     The brand-critical block — logo + Muzzammil ayah
        //     ﴾ وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا ﴿ + سورة المزمّل ـ الآية ٤.
        //     Lives in ui/WarattilSplashScreen.kt. Held for SPLASH_MIN_MS,
        //     then cross-fades into MushaFScreen.
        //
        // Nasser conversation log (2026-04-22):
        //   Round 1: "Please lock it hard and no changes allowed, please
        //             apply the same to the Android version also"
        //   Round 2: "The opening page in the iOS version is not applied
        //             to the Android version…"
        //   Round 3: "The logo has a surrounding gray border. Please
        //             craftily crop that gray border"  [→ CircleShape
        //             clip + oversize, see WarattilSplashScreen.kt]
        //   Round 4: "It is still showing the old intro, then the new
        //             one. The new intro logo is not perfectly cropped"
        //            [→ requiredSize(278.dp) on Image, see splash file]
        //   Round 5: "The old intro is still showing for a second…
        //             please stop showing the old intro first"
        //            [→ strip windowSplashScreenAnimatedIcon from theme,
        //                this file's comment, +
        //                WarattilSplashScreen.kt ayah size bump]
        //
        // Lock contract:
        //   • Don't re-add `windowSplashScreenAnimatedIcon` to the
        //     theme. The icon-less Stage 1 is the whole point — a
        //     branded Stage 1 would reintroduce the double-intro.
        //   • Don't change SPLASH_MIN_MS without asking Nasser. 4000 ms
        //     was set 2026-04-22 to match iOS's minimumSplashDuration.
        //     Dropping below 2500 ms undoes the brand work.
        //   • Don't swap the splash_logo drawable for a different logo.
        //     If Nasser supplies a new logo, overwrite splash_logo.png
        //     IN PLACE so every density bucket stays in sync.
        //   • Don't change windowSplashScreenBackground from #F5F5DC.
        //     That cream is shared across Stage 1, Stage 2, and the
        //     Mushaf page.
        //   • Don't strip the Compose splash to "go back to native
        //     only." Nasser explicitly asked for the full ayah block
        //     on Android parity with iOS.
        //   • Don't add a progress bar or "Loading..." text. If
        //     bootstrap stalls long enough for the user to wonder,
        //     surface an error screen, not a spinner.
        // ══════════════════════════════════════════════════════════════════════
        val splash = installSplashScreen()
        // Kill the default 200 ms exit fade. Stage 1 is a blank cream
        // canvas and Stage 2 is the trademark block — cross-fading
        // between them is a pointless flicker; we want Stage 2 to
        // appear instantly the moment Compose paints its first frame.
        splash.setOnExitAnimationListener { provider -> provider.remove() }
        // LOCKED — matches iOS minimumSplashDuration (4.0 s, WarattilApp.swift).
        val SPLASH_MIN_MS = 4000L

        super.onCreate(savedInstanceState)

        // ── Stability directive (no immersive / no full-screen) ──────────────
        // WARATTIL V2 explicitly does NOT hide the status or navigation bars.
        // The system clock, battery indicator, and gesture-nav bar must
        // remain visible at all times so the user is never disoriented.
        // The Compose root applies systemBarsPadding() + displayCutoutPadding()
        // so nothing is drawn behind the clock / camera / nav bar.
        //
        // (Intentionally no WindowCompat.setDecorFitsSystemWindows / no
        //  WindowInsetsController.hide() calls here.)

        // ── Notification channels (idempotent) ───────────────────────────────
        NotificationHelper.createChannels(this)

        // ── Request POST_NOTIFICATIONS on API 33+ ────────────────────────────
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                notifPermLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        // ── Schedule WorkManager jobs (KEEP policy — safe to call every launch) ─
        WirdReminderWorker.schedule(this)
        HifzRevisionWorker.schedule(this)

        // ── Refresh home-screen widget ────────────────────────────────────────
        WarattilWidgetReceiver.updateAll(this)

        // ── Play In-App Update bootstrap ──────────────────────────────────────
        appUpdateManager = AppUpdateManagerFactory.create(this)
        appUpdateManager.registerListener(updateListener)
        checkForFlexibleUpdate()

        setContent {
            // ── Two-stage splash host ────────────────────────────────────────
            //
            // `showSplash` starts true so the very first Compose frame IS the
            // locked trademark block. Stage 1 is a plain cream canvas (no
            // icon), so the OS hand-off from Stage 1 → Stage 2 reads as
            // "cream loading → branded trademark appears all at once,"
            // with no visible "old intro" interstitial (see the splash
            // block in onCreate for the full reasoning).
            //
            // After SPLASH_MIN_MS a LaunchedEffect flips showSplash → false and
            // Crossfade animates the 700 ms dissolve to MushaFScreen. 700 ms
            // is enough for the reader's eye to notice the transition without
            // feeling slow — it reads as the ayah "settling into" the page.
            var showSplash by remember { mutableStateOf(true) }
            LaunchedEffect(Unit) {
                delay(SPLASH_MIN_MS)
                showSplash = false
            }

            Box(Modifier.fillMaxSize()) {
                Crossfade(
                    targetState    = showSplash,
                    animationSpec  = tween(durationMillis = 700),
                    label          = "splashToMushaf"
                ) { splashVisible ->
                    if (splashVisible) {
                        WarattilSplashScreen()
                    } else {
                        MushaFScreen(viewModel)
                    }
                }

                // Bottom-anchored restart prompt. Slides in once Play has
                // finished the background download. Dismiss («لاحقاً») is
                // allowed — the new binary is already staged, so the install
                // will apply on the next cold launch regardless.
                //
                // Guarded by !showSplash so the banner never appears over the
                // locked trademark block (the Play check fires fast enough
                // that the banner could race into view mid-splash otherwise).
                AnimatedVisibility(
                    visible  = !showSplash && updateReadyState.value,
                    enter    = slideInVertically(initialOffsetY = { it }),
                    exit     = slideOutVertically(targetOffsetY  = { it }),
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .systemBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 16.dp)
                ) {
                    UpdateReadyBanner(
                        onInstall = { appUpdateManager.completeUpdate() },
                        onDismiss = { updateReadyState.value = false }
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Catch two edge cases the listener alone can miss:
        //   (a) the download finished while the app was backgrounded and
        //       the listener fired against a dead composition — re-flip on
        //       resume so the banner reappears.
        //   (b) a flexible update was started in a prior process and the
        //       download is already staged; show the prompt immediately.
        if (::appUpdateManager.isInitialized) {
            appUpdateManager.appUpdateInfo.addOnSuccessListener { info ->
                if (info.installStatus() == InstallStatus.DOWNLOADED) {
                    updateReadyState.value = true
                }
            }
        }
    }

    override fun onDestroy() {
        // Leaking the listener would hold a reference to a no-longer-attached
        // Activity and cause callbacks after destruction. Only unregister if
        // onCreate actually ran far enough to initialize the manager.
        if (::appUpdateManager.isInitialized) {
            appUpdateManager.unregisterListener(updateListener)
        }
        super.onDestroy()
    }

    /** Ask Play whether an update is available, and if so, start the flexible
     *  download flow. All errors are swallowed: the in-app update path is a
     *  bonus, never a blocker for reading — if Play Services is unavailable
     *  or the call fails, the user still gets the Play Store badge path on
     *  their next Store visit. */
    private fun checkForFlexibleUpdate() {
        appUpdateManager.appUpdateInfo.addOnSuccessListener { info ->
            val updatable = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
            val allowed   = info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
            if (updatable && allowed) {
                try {
                    appUpdateManager.startUpdateFlowForResult(
                        info,
                        updateLauncher,
                        AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build()
                    )
                } catch (_: Exception) {
                    // Play failed to open its consent sheet — silent fallback
                    // to the Play Store badge path on the user's next Store
                    // visit. No UX degradation for the reader.
                }
            }
        }
    }
}

/**
 * Pill banner shown at the bottom of the screen once Play has finished
 * downloading the next release. Two affordances:
 *   • «إعادة التشغيل الآن» — primary; calls completeUpdate() which restarts
 *                             the app with the new binary installed
 *   • «لاحقاً»             — dismisses the banner; the download is already
 *                             staged, so the install still applies on the
 *                             next cold launch
 *
 * Styling mirrors AyahActionBar / About-sheet surfaces — rounded edges,
 * cream surface, Mushaf-Green primary — so the prompt reads as part of
 * WARATTIL, not as a generic system popup.
 */
@Composable
private fun UpdateReadyBanner(
    onInstall: () -> Unit,
    onDismiss: () -> Unit,
    modifier : Modifier = Modifier
) {
    Surface(
        modifier        = modifier.fillMaxWidth(),
        color           = WarattilConstants.Colors.CREAM,
        shape           = RoundedCornerShape(16.dp),
        tonalElevation  = 6.dp,
        shadowElevation = 12.dp
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)
        ) {
            Text(
                text       = "تحديث جديد جاهز للتثبيت",
                color      = WarattilConstants.Colors.CHARCOAL,
                fontSize   = 15.sp,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text     = "تم تحميل التحديث في الخلفية — أعد تشغيل التطبيق للاستفادة من التحسينات.",
                color    = WarattilConstants.Colors.CHARCOAL.copy(alpha = 0.75f),
                fontSize = 13.sp
            )
            Spacer(Modifier.height(10.dp))
            Row(
                modifier              = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment     = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss) {
                    Text(
                        text  = "لاحقاً",
                        color = WarattilConstants.Colors.CHARCOAL.copy(alpha = 0.7f)
                    )
                }
                Spacer(Modifier.width(6.dp))
                Button(
                    onClick = onInstall,
                    shape   = RoundedCornerShape(10.dp),
                    colors  = ButtonDefaults.buttonColors(
                        containerColor = WarattilConstants.Colors.MUSHAF_GREEN,
                        contentColor   = WarattilConstants.Colors.CREAM
                    )
                ) {
                    Text(text = "إعادة التشغيل الآن", fontSize = 14.sp)
                }
            }
        }
    }
}
