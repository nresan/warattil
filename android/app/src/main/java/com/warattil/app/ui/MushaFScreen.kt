package com.warattil.app.ui

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.core.ShareUtil
import com.warattil.app.core.WarattilConstants.Hifz
import com.warattil.app.core.WarattilConstants.Layout
import com.warattil.app.core.WarattilConstants.Mushaf
import com.warattil.app.data.Ayah
import com.warattil.app.data.MetadataParser
import com.warattil.app.data.ReadingTargetType
import com.warattil.app.data.SearchResult
import com.warattil.app.data.UserPreferences
import kotlinx.coroutines.launch

// =============================================================================
// Root screen — thin orchestrator
// All composables receive pre-computed ThemeColors; no colour logic lives here.
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MushaFScreen(viewModel: MushaFViewModel) {

    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val font        = rememberQuranFont()
    val scope       = rememberCoroutineScope()
    val context     = LocalContext.current  // Needed by ShareUtil.shareApp to launch the chooser

    // ── State ─────────────────────────────────────────────────────────────────
    val appTheme  by viewModel.appTheme.collectAsState()
    val theme      = WarattilTheme.of(appTheme)

    val bookmarks      by viewModel.bookmarks.collectAsState()
    val searches       by viewModel.searchResults.collectAsState()
    val searching      by viewModel.isSearching.collectAsState()
    val prefs          by viewModel.userPreferences.collectAsState()

    // ── Hifz state — Phase 1 ayah-atomic ──────────────────────────────────────
    //   `memorizedAyahs` is the authoritative set.  `memorizedPages` is a
    //   derived Set<Int> of *fully*-memorized pages, kept so Golden-Fihris
    //   rendering (FihrisSheet) and any other "is this page done?" query
    //   path stays O(1) without rewriting every consumer.
    val memorizedAyahs by viewModel.memorizedAyahs.collectAsState()
    val memorizedPages: Set<Int> = remember(memorizedAyahs) {
        (1..Mushaf.TOTAL_PAGES).filter { p ->
            val keys = MetadataParser.getPageAyahKeys(p)
            keys.isNotEmpty() && keys.all { it in memorizedAyahs }
        }.toSet()
    }

    // ── Pager ────────────────────────────────────────────────────────────────
    val pagerState = rememberPagerState(
        initialPage = (viewModel.startPage - 1).coerceAtLeast(0)
    ) { Mushaf.TOTAL_PAGES }

    // currentPage is read DIRECTLY from pagerState — guaranteed to recompose
    // on every swipe without an async coroutine hop.
    val currentPage = pagerState.currentPage + 1

    // ── Wird-Centric Momentum (Fix #1) ────────────────────────────────────────
    val wirdRatio  = viewModel.wirdProgressRatio(currentPage, prefs)
    val wirdColor  = viewModel.wirdProgressColor(wirdRatio)
    val wirdMsg    = viewModel.wirdProgressMessage(wirdRatio, prefs, currentPage)
    // Resume page for the «↩ تابع وردك · ص N» chip — null when on
    // the wird ribbon (or no wird configured).  The chip only renders
    // when this is non-null; sequential reading keeps it hidden so the
    // page chrome stays calm.  See WirdResumeChip + memory note
    // project_warattil_wird_requirements for the full semantic.
    val wirdResume = viewModel.wirdResumePage(currentPage, prefs)
    val wirdTarget = viewModel.wirdTodayTargetPage(prefs)

    // Search highlight — non-null when a search-result tap set it; the
    // page renderer paints a gold background behind every diacritic-aware
    // match.  Persists across page swipes; cleared by viewModel.clearSearch().
    val searchHighlight by viewModel.searchHighlight.collectAsState()

    // ── Optimistic bookmark state ─────────────────────────────────────────────
    var pendingBkm by remember { mutableStateOf<Set<Int>?>(null) }
    val bkmPages   = pendingBkm ?: bookmarks.map { it.pageNumber }.toSet()
    LaunchedEffect(bookmarks) { pendingBkm = null }

    fun toggleBkm(page: Int) {
        pendingBkm = if (bkmPages.contains(page)) bkmPages - page else bkmPages + page
        viewModel.toggleBookmark(page)
    }

    // ── Overlay visibility ────────────────────────────────────────────────────
    var showSearch      by remember { mutableStateOf(false) }
    var showFihris      by remember { mutableStateOf(false) }
    var showWird        by remember { mutableStateOf(false) }
    var showBkm         by remember { mutableStateOf(false) }
    var showMenu        by remember { mutableStateOf(false) }
    var showHifzLog     by remember { mutableStateOf(false) }
    var showBulkPicker  by remember { mutableStateOf(false) }
    var showUsageGuide  by remember { mutableStateOf(false) }
    var showAbout       by remember { mutableStateOf(false) }
    var showAzanSettings by remember { mutableStateOf(false) }
    // Share-preview sheets (BLUEPRINT §11.4 / §11.7, April 2026).  Each one
    // mounts the corresponding card inside a `rememberGraphicsLayer` Box so
    // the user can see what they're about to send before firing the system
    // chooser.  Mirrors V3 HifzLogSheet's proven on-screen capture pattern.
    var showShareDaily  by remember { mutableStateOf(false) }
    var showShareInvite by remember { mutableStateOf(false) }
    // Meanings sheet (Ghareeb + tafsir placeholders).  Opens from the book
    // icon in AyahActionBar; scoped to the anchor ayah captured at open
    // time, so closing the sheet doesn't affect the long-press selection.
    var meaningsForAyah by remember { mutableStateOf<Ayah?>(null) }

    // Which tab the Hifz sheet opens on.  Normally 0 (stats), but the bulk
    // picker flow flips this to 1 (heatmap) before re-opening so the user
    // sees their تثبيت land immediately without having to flip tabs.
    var hifzInitialTab   by remember { mutableIntStateOf(0) }

    // ── Tier-crossing celebration ─────────────────────────────────────────
    //   ViewModel emits `tierCelebration` whenever the user crosses into a
    //   higher hifz tier for the first time (1..6 — see Hifz.hifzTier).
    //   We hold the pending tier here so the dialog stays visible across
    //   recompositions and only dismisses on explicit user action.
    var celebrateTier by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(Unit) {
        viewModel.tierCelebration.collect { tier ->
            celebrateTier = tier
        }
    }

    // ── Long-press ayah selection (task #2) ──────────────────────────────────
    // Ephemeral, page-scoped state. A long-press inside any AyahBlock lifts
    // the selected ayah here; the floating action bar below renders while
    // `selectedAyah != null`. The LaunchedEffect below clears the selection
    // whenever the pager lands on a new page, so swipes naturally dismiss
    // the bar without an explicit "close" interaction.
    //
    // Multi-ayah range (BLUEPRINT §11.3 — April 2026)
    // ------------------------------------------------
    // `endAyah` tracks the trailing ayah of a contiguous selection; it snaps
    // back to the anchor whenever a new anchor is long-pressed or the pager
    // moves, so the range UX is opt-in and never outlives the current pill.
    // The ± chips in AyahActionBar mutate endAyah; single-ayah mode is
    // preserved by defaulting endAyah to the anchor ayah's number.
    var selectedAyah by remember { mutableStateOf<Ayah?>(null) }
    var endAyah      by remember { mutableStateOf<Int?>(null) }
    val onAyahLongPress: (Ayah) -> Unit = { a ->
        selectedAyah = a
        endAyah      = a.ayah
    }
    val onActionBarDismiss: () -> Unit  = {
        selectedAyah = null
        endAyah      = null
    }

    // ── Yesterday acknowledgement («أمس» pill) ───────────────────────────────
    // Computed ONCE per composition, the first time userPreferences becomes
    // non-null (flow is Eagerly-started so this is effectively the first
    // frame of a normal app open).  A `yesterdayChecked` latch ensures the
    // pill doesn't spuriously re-trigger if `prefs` gets re-emitted mid-
    // session (e.g. the user edits their wird target via WirdDialog).
    //
    // Returns null in any of these cases — pill skipped cleanly:
    //   • no wird configured
    //   • last_read_date isn't yesterday (didn't read yesterday OR already
    //     read today so it's not "first open of a new day" anymore)
    //   • last_acknowledged_date is already today
    //   • yesterday's pages-read computes to zero
    //
    // See [MushaFViewModel.yesterdayAcknowledgement] for the full guard
    // logic and [feedback_warattil_no_debt_accounting] for the principle.
    var yesterdayAck     by remember { mutableStateOf<DailyAcknowledgement?>(null) }
    var yesterdayChecked by remember { mutableStateOf(false) }
    LaunchedEffect(prefs) {
        if (!yesterdayChecked) {
            // One-shot: fire exactly once per composition.  Prefs may be
            // null on first emission (flow Eagerly-started but not yet
            // populated) — the VM function gracefully returns null in
            // that case, so we still latch `checked = true` to prevent
            // re-triggering on subsequent prefs emissions.  WelcomeBack
            // is returned even when prefs is null (no wird required)
            // as long as last_read_date < today, which is exactly the
            // "returning reader" case we want to honour.
            yesterdayChecked = true
            yesterdayAck = viewModel.yesterdayAcknowledgement()
        }
    }

    // ── Side-effects ──────────────────────────────────────────────────────────
    LaunchedEffect(Unit) {
        viewModel.navigationEvent.collect { targetPage ->
            scope.launch { pagerState.scrollToPage(targetPage - 1) }
        }
    }
    LaunchedEffect(pagerState.currentPage) {
        viewModel.onPageChanged(pagerState.currentPage)
        // Swipe implicitly dismisses the long-press action bar — the reader's
        // selection belongs to the page they're leaving, not the one arriving.
        selectedAyah = null
        endAyah      = null
    }

    // ── Page metadata for header ──────────────────────────────────────────────
    val pageState by viewModel.getPageFlow(currentPage).collectAsState()
    val surahName  = (pageState as? PageUiState.Success)?.content?.surahName ?: ""
    val juzNum     = (pageState as? PageUiState.Success)?.content?.juzNumber  ?: 0
    // pageAyahs is lifted up so the AyahActionBar's range-share formatter
    // never hops to the repository while the pill is open.  The list is
    // read-only here; the database is the source of truth and it reached
    // us via PageContent during the normal page-load path.
    val pageAyahs  = (pageState as? PageUiState.Success)?.content?.ayahs.orEmpty()

    // ── Multi-ayah selection — visual-highlight set ──────────────────────────
    // When the user expands the selection via the AyahActionBar's + chip
    // (mutates `endAyah`), the body's highlight should extend to cover
    // every ayah in [anchor.ayah .. endAyah] within the anchor's surah.
    // We compute the set of row-IDs to highlight here at the parent so
    // both portrait and landscape PageContent call sites get the same
    // value, and so the Body composable's existing per-ayah `id in set`
    // check stays a single-line check (no surah/ayah maths inside Body).
    val selectedAyahIds: Set<Int> = remember(selectedAyah, endAyah, pageAyahs) {
        val anchor      = selectedAyah ?: return@remember emptySet<Int>()
        val anchorSurah = anchor.surah ?: return@remember emptySet<Int>()
        val anchorNum   = anchor.ayah  ?: return@remember emptySet<Int>()
        val end         = endAyah ?: anchorNum
        pageAyahs.asSequence()
            .filter {
                it.surah == anchorSurah &&
                it.ayah != null && it.ayah in anchorNum..end &&
                it.id != null
            }
            .mapNotNull { it.id }
            .toSet()
    }

    // ── Shared callbacks ──────────────────────────────────────────────────────
    // Per-page memorization ratio (0 .. 1) drives the header strip's tri-state
    // tint via Hifz.stripAlpha.  The Memorize callback now runs the ViewModel's
    // complete-or-clear page toggle (togglePage) — if any ayah is missing on
    // the page it completes the page; if the page is fully memorized it
    // clears it.  Matches the old "toggle memorized" gesture semantically.
    val pageMemRatio: Float = remember(memorizedAyahs, currentPage) {
        val keys = MetadataParser.getPageAyahKeys(currentPage)
        if (keys.isEmpty()) 0f
        else keys.count { it in memorizedAyahs }.toFloat() / keys.size.toFloat()
    }
    val onBookmark    = { toggleBkm(currentPage) }
    val onMemorize: () -> Unit = { viewModel.togglePage(currentPage) }
    val onThemeCycle  = { viewModel.cycleTheme() }
    val onSearchOpen  = { showSearch = true }
    val onMoreOpen    = { showMenu  = true }
    val onMenuDismiss = { showMenu  = false }
    val onFihrisOpen  = { showMenu  = false; showFihris  = true }
    val onWirdOpen    = { showMenu  = false; showWird    = true }
    val onBkmOpen     = { showMenu  = false; showBkm     = true }
    val onHifzLogOpen    = { showMenu  = false; showHifzLog    = true }
    val onUsageGuideOpen = { showMenu  = false; showUsageGuide = true }
    val onAboutOpen      = { showMenu  = false; showAbout      = true }
    val onAzanSettingsOpen = { showMenu = false; showAzanSettings = true }
    // ── Overflow-menu share surfaces (BLUEPRINT §11.4 + §11.7 — April 2026) ─
    //
    // Each callback opens a small bottom-sheet preview of the card that will
    // be shared.  The sheet renders the card inside a `rememberGraphicsLayer`
    // Box (the proven V3 HifzLogSheet capture pattern) and exposes a
    // "مشاركة" primary button that fires the actual system chooser.  This
    // replaces the earlier offscreen-translated-graphicsLayer approach used
    // in V2 — Compose occasionally skips the draw pass for offscreen
    // children, yielding blank bitmaps, and users couldn't see what they
    // were about to send.
    val onShareDaily: () -> Unit = { showMenu = false; showShareDaily  = true }
    val onShareClick: () -> Unit = { showMenu = false; showShareInvite = true }

    // ── Daily-reading card data ──────────────────────────────────────────────
    //   Built at the call site from the ViewModel's wird helpers.  The
    //   `pagesReadToday` / `dailyPagesGoal` pair is null when no wird is
    //   configured — the card gracefully falls back to the "page X of 604"
    //   readout (see DailyReadingShareCard.mainStatText).
    val dailyCardData: DailyReadingCardData = run {
        val p             = prefs
        val wirdActive    = p?.wirdStartDate != null
        val dailyPages    = if (wirdActive) viewModel.wirdDailyPages(p!!) else null
        val todayTarget   = if (wirdActive) viewModel.wirdTodayTargetPage(p) else null
        val todayStart    = if (wirdActive && dailyPages != null && todayTarget != null)
                                (todayTarget - dailyPages + 1).coerceAtLeast(1) else null
        val pagesReadToday = if (todayStart != null)
                                (currentPage - todayStart + 1).coerceAtLeast(0) else null
        DailyReadingCardData(
            currentPage     = currentPage,
            surahName       = surahName,
            juzNumber       = juzNum,
            progressRatio   = wirdRatio,
            progressMessage = wirdMsg,
            progressColor   = wirdColor,
            pagesReadToday  = pagesReadToday,
            dailyPagesGoal  = dailyPages
        )
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    // The Compose root is kept simple: the system bars (clock, battery,
    // gesture-nav) are ALWAYS visible — no immersive mode. The portrait
    // Scaffold's topBar carries statusBarsPadding internally and the
    // bottom footer carries navigationBarsPadding, so nothing is drawn
    // behind the system chrome.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {

        if (isLandscape) {
            // Landscape: full-screen immersive box — cream background spans edge-to-edge,
            // but content (pager, header, footer) is inset by the system bars and
            // display cutout so nothing is clipped by the camera / rounded corners.
            Box(modifier = Modifier.fillMaxSize().background(theme.background)) {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    HorizontalPager(
                        state                   = pagerState,
                        modifier                = Modifier
                            .fillMaxSize()
                            .statusBarsPadding()
                            .navigationBarsPadding()
                            .displayCutoutPadding()
                            .padding(top = 28.dp, bottom = 8.dp),
                        beyondViewportPageCount = 1,
                        key                     = { it }
                    ) { idx ->
                        val st by viewModel.getPageFlow(idx + 1).collectAsState()
                        // Only route long-presses to the currently-visible
                        // page — the pager renders neighbours off-screen for
                        // pre-warming, and we don't want a stray hit on an
                        // adjacent page to move the bar onto it.
                        val isActivePage = idx == pagerState.currentPage
                        PageContent(
                            state           = st,
                            font            = font,
                            theme           = theme,
                            isLandscape     = true,
                            selectedAyahIds = if (isActivePage) selectedAyahIds else emptySet(),
                            searchHighlight = searchHighlight,
                            onAyahLongPress = if (isActivePage) onAyahLongPress else null
                        )
                    }
                }
                LandscapeHeaderStrip(
                    surahName = surahName, juzNum = juzNum, currentPage = currentPage,
                    font = font, theme = theme,
                    isBookmarked         = bkmPages.contains(currentPage),
                    pageMemorizationRatio = pageMemRatio,
                    onBookmark    = onBookmark, onMemorize = onMemorize,
                    onThemeCycle  = onThemeCycle,
                    onSearch      = onSearchOpen,
                    onMore        = onMoreOpen,
                    menuExpanded  = showMenu, onMenuDismiss = onMenuDismiss,
                    onFihris     = onFihrisOpen, onWird = onWirdOpen, onBkm = onBkmOpen,
                    onHifzLog    = onHifzLogOpen,
                    onAzanSettings = onAzanSettingsOpen,
                    onUsageGuide = onUsageGuideOpen,
                    onAbout      = onAboutOpen,
                    onShareDaily = onShareDaily,
                    onShare      = onShareClick,
                    modifier     = Modifier
                        .align(Alignment.TopCenter)
                        .displayCutoutPadding()
                )
                LandscapeMomentumStrip(
                    wirdRatio = wirdRatio, wirdColor = wirdColor,
                    modifier  = Modifier
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                )
            }
        } else {
            // Portrait: Scaffold with pinned header + footer
            Scaffold(
                containerColor = theme.background,
                topBar = {
                    MushaFHeader(
                        surahName = surahName, juzNum = juzNum, currentPage = currentPage,
                        font = font, theme = theme,
                        isBookmarked         = bkmPages.contains(currentPage),
                        pageMemorizationRatio = pageMemRatio,
                        onBookmark    = onBookmark, onMemorize = onMemorize,
                        onDarkMode    = onThemeCycle,
                        onSearch      = onSearchOpen,
                        onMore        = onMoreOpen,
                        menuExpanded  = showMenu, onMenuDismiss = onMenuDismiss,
                        onFihris     = onFihrisOpen, onWird = onWirdOpen, onBkm = onBkmOpen,
                        onHifzLog    = onHifzLogOpen,
                        onAzanSettings = onAzanSettingsOpen,
                        onUsageGuide = onUsageGuideOpen,
                        onAbout      = onAboutOpen,
                        onShareDaily = onShareDaily,
                        onShare      = onShareClick
                    )
                },
                bottomBar = {
                    // Chip is now inline inside the footer's first row
                    // (2026-04-27 pt. 6) — Nasser feedback: stacking the
                    // chip ABOVE the motivation message wasted ~24dp of
                    // bottomBar height that could go to body content.
                    // MushaFFooter takes the chip params; FooterWirdActive
                    // composes [message + chip] on the same row.
                    MushaFFooter(
                        currentPage     = currentPage,
                        wirdRatio       = wirdRatio, wirdColor = wirdColor, wirdMessage = wirdMsg,
                        font            = font, theme = theme, prefs = prefs, wirdTarget = wirdTarget,
                        wirdResumePage  = wirdResume,
                        onWirdResumeTap = { wirdResume?.let(viewModel::navigateToPage) },
                        // Tappable line in MODE B opens WirdDialog
                        // directly — bypasses the overflow menu so
                        // no-wird users have a one-tap path to start.
                        onWirdSetClick  = { showWird = true }
                    )
                }
            ) { pad ->
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    HorizontalPager(
                        state                   = pagerState,
                        // pad accounts for the topBar + bottomBar measured
                        // heights; BODY_BOTTOM_BREATHING (PIPELINE #48) adds
                        // the 12 dp safety cushion that keeps the last line
                        // of dense pages clear of the momentum bar — the
                        // adaptive font engine picks a slightly smaller sp
                        // because BoxWithConstraints inside PageContent
                        // inherits the reduced maxHeight.
                        modifier                = Modifier
                            .fillMaxSize()
                            .padding(pad)
                            .padding(bottom = Layout.BODY_BOTTOM_BREATHING),
                        beyondViewportPageCount = 1,
                        key                     = { it }
                    ) { idx ->
                        val st by viewModel.getPageFlow(idx + 1).collectAsState()
                        // Only route long-presses to the currently-visible
                        // page — see the landscape branch for the rationale.
                        val isActivePage = idx == pagerState.currentPage
                        PageContent(
                            state           = st,
                            font            = font,
                            theme           = theme,
                            isLandscape     = false,
                            selectedAyahIds = if (isActivePage) selectedAyahIds else emptySet(),
                            searchHighlight = searchHighlight,
                            onAyahLongPress = if (isActivePage) onAyahLongPress else null
                        )
                    }
                }
            }
        }

        // ── Long-press action bar ─────────────────────────────────────────────
        // Rendered above the pager content but below the modal sheets. The
        // selected ayah itself carries the primary visual feedback (a soft
        // 14% accent highlight); the bar is a one-hand-reachable Copy /
        // Share affordance anchored at the top of the content area, inset
        // below the header strip in both portrait and landscape.
        //
        // Dismiss paths (deliberately three, no backdrop):
        //   1. Tap Copy or Share — the action fires and clears selection.
        //   2. Swipe to another page — LaunchedEffect above clears.
        //   3. Long-press a different ayah — replaces the selection.
        //
        // An invisible full-screen backdrop was considered but rejected:
        // `Modifier.clickable` consumes pointer-down events, so a backdrop
        // would eat long-presses aimed at other ayahs and force a two-tap
        // ritual (dismiss → re-long-press) to change selection. Leaving
        // the page reachable means subsequent long-presses just work.
        if (selectedAyah != null) {
            val current = selectedAyah!!
            // Derived ayah-level memorized state for the selected ayah.  The
            // bar's first action — the لوح glyph — flips tint between gold-
            // full (memorized) and dim gold (not yet) without dismissing the
            // bar, so users can verify before moving on.  The callback routes
            // to ViewModel.toggleAyah, which adds the single ayah key to the
            // authoritative Set<Long>.
            val currentSura = current.surah ?: 0
            val currentAya  = current.ayah  ?: 0
            val currentAyahMemorized = currentSura > 0 && currentAya > 0 &&
                    Hifz.ayahKey(currentSura, currentAya) in memorizedAyahs
            val onToggleMemorizeAyah: () -> Unit = {
                if (currentSura > 0 && currentAya > 0) {
                    viewModel.toggleAyah(currentSura, currentAya)
                }
            }
            // Range-selection bounds: the pill can only extend forward as far
            // as the last ayah of the anchor's surah ON THE CURRENT PAGE.
            // Cross-page or cross-surah extension would require hopping to
            // the repository while the pill is open — we defer that to a
            // later iteration and keep the selection page-local for now.
            val resolvedEnd = endAyah ?: currentAya
            val lastAyahOfSurahOnPage: Int = pageAyahs
                .asSequence()
                .filter { it.surah == currentSura }
                .mapNotNull { it.ayah }
                .maxOrNull() ?: currentAya
            val canExtend = resolvedEnd < lastAyahOfSurahOnPage
            val canShrink = resolvedEnd > currentAya
            // Headroom offset accounts for the pinned header strip above.
            // Portrait uses ~Scaffold topBar height (56dp) + breathing
            // room; landscape uses a smaller value because the landscape
            // strip is compact.
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .padding(top = if (isLandscape) 40.dp else 68.dp)
            ) {
                AyahActionBar(
                    ayah              = current,
                    isMemorized       = currentAyahMemorized,
                    onToggleMemorize  = onToggleMemorizeAyah,
                    theme             = theme,
                    onDismiss         = onActionBarDismiss,
                    endAyah           = resolvedEnd,
                    pageAyahs         = pageAyahs,
                    onExtendForward   = {
                        if (canExtend) endAyah = (resolvedEnd + 1)
                            .coerceAtMost(lastAyahOfSurahOnPage)
                    },
                    onShrinkBackward  = {
                        endAyah = (resolvedEnd - 1).coerceAtLeast(currentAya)
                    },
                    canExtendForward  = canExtend,
                    canShrinkBackward = canShrink,
                    // Capture the anchor ayah at open-time — the
                    // meanings sheet stays scoped to it even if the
                    // user later expands the +/- range.
                    onOpenMeanings    = { meaningsForAyah = current },
                    modifier          = Modifier.align(Alignment.TopCenter)
                )
            }
        }

        // ── Daily acknowledgement pill («أمس» / «أهلاً بعودتك») ──────────────
        // Once-per-day calm greeting that auto-fades after ~5 s.  Rendered
        // as a peer overlay to the AyahActionBar so z-order stays sane
        // if the two coexist briefly (user long-presses in the first
        // few seconds of the day's first open).  The pill is small and
        // non-interactive — swipes, taps, and long-presses pass straight
        // through to the Mushaf page underneath.  See
        // [YesterdayAcknowledgementPill] and
        // [MushaFViewModel.yesterdayAcknowledgement] for the full gate
        // logic and `feedback_warattil_no_debt_accounting` for the
        // product principle.
        yesterdayAck?.let { ack ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .padding(top = if (isLandscape) 40.dp else 68.dp),
                contentAlignment = Alignment.TopCenter
            ) {
                YesterdayAcknowledgementPill(
                    ack            = ack,
                    theme          = theme,
                    onAcknowledged = { viewModel.markYesterdayAcknowledged() }
                )
            }
        }

        // ── Overlays ──────────────────────────────────────────────────────────
        if (showSearch) {
            val occurrences  by viewModel.searchOccurrences.collectAsState()
            val initialQuery by viewModel.searchQuery.collectAsState()
            SearchSheet(
                initialQuery = initialQuery,
                results      = searches, loading = searching, font = font, theme = theme,
                occurrences  = occurrences,
                onQuery      = { viewModel.onSearchQueryChanged(it) },
                onClear      = { viewModel.clearSearch() },
                // Tapping a result navigates to the matched page AND sets
                // the inline highlight so every occurrence of the query
                // on that page (and on any page the user swipes to next)
                // gets a gold-tinted background.  Highlight clears via
                // viewModel.clearSearch() — see searchHighlight doc.
                onNav        = { page ->
                    showSearch = false
                    viewModel.setSearchHighlight(initialQuery)
                    viewModel.navigateToPage(page)
                },
                // 2026-04-27: was clearing the search on dismiss.  Nasser
                // wants the previous query + results preserved across
                // re-opens so a returning reader knows which word their
                // results came from.  Clearing happens only when the
                // user explicitly taps the trailing-X inside the field
                // (which calls onClear → viewModel.clearSearch()).
                onDismiss    = { showSearch = false }
            )
        }
        if (showFihris) FihrisSheet(
            surahPages     = viewModel.surahStartPages,
            juzPages       = viewModel.juzStartPages,
            memorizedPages = memorizedPages,
            font = font, theme = theme,
            onNav      = { page -> showFihris = false; viewModel.navigateToPage(page) },
            onDismiss  = { showFihris = false }
        )
        if (showHifzLog) HifzLogSheet(
            memorizedAyahs  = memorizedAyahs,
            surahStartPages = viewModel.surahStartPages,
            juzStartPages   = viewModel.juzStartPages,
            font    = font,
            theme   = theme,
            onNav   = { page -> showHifzLog = false; viewModel.navigateToPage(page) },
            onBulkEntry = { showHifzLog = false; showBulkPicker = true },
            onDismiss = { showHifzLog = false; hifzInitialTab = 0 },
            initialTab = hifzInitialTab
        )
        if (showBulkPicker) HifzBulkPickerSheet(
            initialMemorized = memorizedAyahs,
            surahNames       = { idx -> MetadataParser.getSuraName(idx) },
            font             = font,
            theme            = theme,
            onApply          = { toAdd, toRemove ->
                // Commit the delta — either side may be empty.
                if (toAdd.isNotEmpty())    viewModel.setAyahsMemorized(toAdd,    true)
                if (toRemove.isNotEmpty()) viewModel.setAyahsMemorized(toRemove, false)
                // Auto-jump to the heatmap tab so the user sees their تثبيت
                // land immediately.  hifzInitialTab resets on Hifz dismiss.
                showBulkPicker = false
                hifzInitialTab = 1
                showHifzLog    = true
            },
            onDismiss        = { showBulkPicker = false }
        )
        if (showWird) WirdDialog(
            page = currentPage, prefs = prefs, theme = theme,
            onSet     = { t, v -> viewModel.setWirdTarget(t, v, currentPage); showWird = false },
            // 2026-04-27: was viewModel.resetProgress() — which ALSO
            // deleted every bookmark and kicked the reader back to page
            // 1.  «إيقاف الورد» now calls cancelWird() which clears
            // ONLY the wird state (matches what the button label
            // promises).  See cancelWird() doc comment for the full
            // diagnosis.
            onReset   = { viewModel.cancelWird(); showWird = false },
            onDismiss = { showWird = false }
        )
        if (showBkm) BookmarkSheet(
            bookmarks  = bookmarks, font = font, theme = theme,
            onNav      = { page -> showBkm = false; viewModel.navigateToPage(page) },
            onDelete   = { viewModel.deleteBookmark(it); Unit },
            onClearAll = { viewModel.clearAllBookmarks(); Unit },
            onDismiss  = { showBkm = false }
        )

        if (showUsageGuide) UsageGuideSheet(
            font      = font,
            theme     = theme,
            onDismiss = { showUsageGuide = false }
        )

        if (showAbout) AboutSheet(
            font      = font,
            theme     = theme,
            onDismiss = { showAbout = false }
        )

        if (showAzanSettings) AzanSettingsSheet(
            font      = font,
            theme     = theme,
            onDismiss = { showAzanSettings = false }
        )

        // ── Meanings sheet — Ghareeb + tafsir placeholders ───────────────────
        // Opened from the book icon in AyahActionBar.  Scoped to the anchor
        // ayah captured at open-time so closing it doesn't dismiss the
        // long-press selection.  See AyahMeaningsSheet for section layout.
        meaningsForAyah?.let { ayah ->
            val sura = ayah.surah ?: return@let
            val aya  = ayah.ayah  ?: return@let
            AyahMeaningsSheet(
                suraNumber = sura,
                ayaNumber  = aya,
                font       = font,
                theme      = theme,
                onDismiss  = { meaningsForAyah = null }
            )
        }

        // ── Share-preview sheets ─────────────────────────────────────────────
        //   On-screen preview + capture sheets.  Each mounts the corresponding
        //   card inside a `rememberGraphicsLayer` Box, snapshots on tap, and
        //   hands the Bitmap to the right ShareUtil path.
        if (showShareDaily) DailyReadingSharePreviewSheet(
            data      = dailyCardData,
            font      = font,
            theme     = theme,
            onShare   = { bmp ->
                showShareDaily = false
                ShareUtil.shareDailyReading(context, bmp)
            },
            onDismiss = { showShareDaily = false }
        )
        if (showShareInvite) AppInviteSharePreviewSheet(
            font      = font,
            theme     = theme,
            onShare   = { bmp ->
                showShareInvite = false
                ShareUtil.shareAppInvite(context, bmp)
            },
            onDismiss = { showShareInvite = false }
        )

        // ── Celebration — tier crossing ───────────────────────────────────
        //   Renders above every other sheet so a crossing triggered from
        //   the bulk-picker apply path lands in front of the re-opened
        //   Hifz log sheet.  The dialog derives its juz count from the
        //   current memorizedAyahs set — no need to plumb the count through
        //   the event because memorizedAyahs is guaranteed to be current by
        //   the time the event arrives (ViewModel updates the StateFlow
        //   before emitting).
        celebrateTier?.let { tier ->
            val juzCount = remember(memorizedAyahs) {
                (1..Mushaf.TOTAL_JUZAA).count { j ->
                    val keys = MetadataParser.getJuzAyahKeys(j)
                    keys.isNotEmpty() && keys.all { it in memorizedAyahs }
                }
            }
            HifzCelebrationDialog(
                tier      = tier,
                juzCount  = juzCount,
                font      = font,
                theme     = theme,
                onDismiss = { celebrateTier = null }
            )
        }
    }
}

// =============================================================================
// Search sheet
// =============================================================================

/**
 * Arabic plural form for "occurrence" — Nasser 2026-04-25.
 *   1   → "مرة واحدة"  (singular)
 *   2   → "مرتان"      (dual)
 *   3-10 → "N مرات"   (plural)
 *   11+ → "N مرة"     (singular returns after 10 in classical Arabic)
 *   0   → "" (caller hides the row)
 */
private fun occurrencesLabel(count: Int): String = when (count) {
    0    -> ""
    1    -> "مرة واحدة"
    2    -> "مرتان"
    in 3..10 -> "${count.toArabicDigits()} مرات"
    else -> "${count.toArabicDigits()} مرة"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchSheet(
    initialQuery : String,
    results      : List<SearchResult>,
    loading      : Boolean,
    font         : QuranFontInfo,
    theme        : ThemeColors,
    // Total substring occurrences across all matched ayahs (NOT the ayah
    // count — an ayah with the term twice contributes 2).  The label
    // beside the input updates live as the user refines the query, so a
    // search that narrows the term shows a smaller count.
    occurrences  : Int,
    onQuery      : (String) -> Unit,
    onClear      : () -> Unit,
    onNav        : (Int) -> Unit,
    onDismiss    : () -> Unit
) {
    // Pre-seeded with the last query (Nasser, 2026-04-27) so re-opening
    // the sheet shows what the user was searching for last — they don't
    // have to remember which word their results came from.  Keyed off
    // initialQuery so a fresh ViewModel state propagates in cleanly.
    var query by remember(initialQuery) { mutableStateOf(initialQuery) }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = theme.background) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .padding(horizontal = 16.dp)
        ) {
            Text(
                "البحث في القرآن الكريم",
                color = theme.accent, fontSize = 17.sp, fontWeight = FontWeight.Bold,
                fontFamily = font.family, modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
                textAlign = TextAlign.Center, style = TextStyle(textDirection = TextDirection.Rtl)
            )
            // Field + occurrence-count chip on ONE row (Nasser 2026-04-27
            // pt. 5): the count was below the field at 28sp — visible but
            // wasted vertical space when results were already lined up
            // below.  Same row keeps both visible without pushing the
            // results list down.  Field takes weight(1f), count pill
            // sits on the visual-LEFT (RTL leading edge — where the eye
            // settles after typing).  Chip dropped to 22sp Bold so the
            // row height tracks the OutlinedTextField's natural height.
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                Row(
                    modifier              = Modifier.fillMaxWidth(),
                    verticalAlignment     = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    OutlinedTextField(
                        value         = query,
                        onValueChange = { query = it; onQuery(it) },
                        placeholder   = { Text("ابحث عن كلمة أو آية...", fontFamily = font.family, style = TextStyle(textDirection = TextDirection.Rtl)) },
                        modifier      = Modifier.weight(1f),
                        singleLine    = true,
                        colors        = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor   = theme.accent,
                            unfocusedBorderColor = theme.accent.copy(alpha = 0.4f),
                            focusedTextColor     = theme.text,
                            unfocusedTextColor   = theme.text,
                            cursorColor          = theme.accent
                        ),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { onQuery(query) })
                    )
                    if (occurrences > 0) {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(14.dp))
                                .background(theme.accent.copy(alpha = 0.10f))
                                .border(
                                    width = 1.dp,
                                    color = theme.accent.copy(alpha = 0.45f),
                                    shape = RoundedCornerShape(14.dp)
                                )
                                .padding(horizontal = 14.dp, vertical = 10.dp)
                        ) {
                            // FontFamily.Default — NOT font.family (Hafs Uthmanic).
                            // The Quran font has a GSUB ligature that substitutes
                            // up to 2 digits into a single Mushaf-style rosette
                            // glyph; 3-digit counts (e.g. ١٠٣) render as a
                            // 2-rosette split (Nasser bug 2026-04-27).  System
                            // font renders all digits cleanly without the
                            // substitution.  Same pattern MushaFFooter's
                            // percentage label and the FihrisSheet page badges
                            // already use.
                            Text(
                                text       = occurrencesLabel(occurrences),
                                color      = theme.accent,
                                fontSize   = 22.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Default,
                                style      = TextStyle(textDirection = TextDirection.Rtl)
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
            if (loading) LinearProgressIndicator(modifier = Modifier.fillMaxWidth(), color = theme.accent)

            // Whole result list rendered under an RTL CompositionLocal
            // (Nasser 2026-04-27: previously relied on inherited LTR +
            // SpaceBetween, which left the «ص N» page-number Text rendering
            // as «N ص» on some devices because the Text had no explicit
            // textDirection).  Each row is now declared RTL end-to-end:
            //   • Row laid out RTL — first child sits on visual RIGHT.
            //   • Children reordered so the surah label comes first
            //     (right edge — Arabic newspaper convention) and the
            //     page-number sits second (left edge).
            //   • Every Text carries explicit Rtl textDirection.
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 380.dp)) {
                    items(results) { r ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onNav(r.pageNumber) }
                                .padding(vertical = 8.dp, horizontal = 4.dp)
                        ) {
                            Row(
                                modifier              = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                // Surah + ayah label — visual RIGHT under RTL.
                                Text(
                                    "${r.surahName} ﴿${r.ayahNumber.toArabicDigits()}﴾",
                                    color      = theme.accent,
                                    fontSize   = 13.sp,
                                    fontFamily = font.family,
                                    fontWeight = FontWeight.Bold,
                                    style      = TextStyle(textDirection = TextDirection.Rtl)
                                )
                                // Page number — visual LEFT under RTL.
                                Text(
                                    "ص ${r.pageNumber.toArabicDigits()}",
                                    color    = theme.accent.copy(alpha = 0.7f),
                                    fontSize = 12.sp,
                                    style    = TextStyle(textDirection = TextDirection.Rtl)
                                )
                            }
                            Spacer(Modifier.height(3.dp))
                            Text(
                                r.text.take(110),
                                color      = theme.text,
                                fontSize   = 14.sp,
                                fontFamily = font.family,
                                maxLines   = 2,
                                style      = TextStyle(textDirection = TextDirection.Rtl, textAlign = TextAlign.Start),
                                modifier   = Modifier.fillMaxWidth()
                            )
                            HorizontalDivider(modifier = Modifier.padding(top = 6.dp), color = theme.divider)
                        }
                    }
                    if (results.isEmpty() && !loading && query.isNotBlank()) item {
                        // Action-oriented empty state — suggest the next step
                        // rather than stating absence.
                        Text(
                            "لم نجد ما يطابق بحثك — جرِّب كلمةً أخرى",
                            color     = theme.text.copy(alpha = 0.45f),
                            modifier  = Modifier.fillMaxWidth().padding(32.dp),
                            textAlign = TextAlign.Center,
                            fontFamily = font.family,
                            style     = TextStyle(textDirection = TextDirection.Rtl)
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

// =============================================================================
// Fihris sheet
// =============================================================================

/** Deep Gold constant mirrored here for Golden Fihris rendering */
private val FIHRIS_GOLD     = androidx.compose.ui.graphics.Color(0xFF996515)
private val FIHRIS_GOLD_BG  = androidx.compose.ui.graphics.Color(0xFFFFF8E1)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FihrisSheet(
    surahPages    : Map<Int, Int>,
    juzPages      : Map<Int, Int>,
    memorizedPages: Set<Int>,
    font          : QuranFontInfo,
    theme         : ThemeColors,
    onNav         : (Int) -> Unit,
    onDismiss     : () -> Unit
) {
    var tab by remember { mutableIntStateOf(0) }

    // ── Filter state (Nasser 2026-04-22) ─────────────────────────────────────
    //
    // The Fihris is long: 114 surahs + 604 pages. Without a filter the user
    // has to scroll the full list to reach (say) سورة مريم or صفحة ٣٥٠.
    // A small search box under each list lets students filter by name or
    // by page number directly.
    //
    //   • Surah tab — match the Arabic surah name (substring), or the
    //     surah index as Western digits (1-114) or as Eastern Arabic
    //     digits (١-١١٤). All three variants so the field is forgiving
    //     whichever keyboard the user has up.
    //   • Pages tab — match the page number in both digit variants.
    //   • Juz tab — NO filter on purpose. Only 30 rows; a search box would
    //     just be visual noise.
    //
    // Mirrors the iOS FihrisSheet implementation shipped 2026-04-22 in
    // `ios/Warattil/Warattil/UI/MushaFSheets.swift`.
    var surahFilter by remember { mutableStateOf("") }
    var pageFilter  by remember { mutableStateOf("") }

    val filteredSurahs: List<Int> = remember(surahFilter) {
        val q = surahFilter.trim()
        if (q.isEmpty()) (1..114).toList()
        else (1..114).filter { n ->
            val name = MetadataParser.getSuraName(n)
            name.contains(q) || n.toString().contains(q) || n.toArabicDigits().contains(q)
        }
    }

    val filteredPages: List<Int> = remember(pageFilter) {
        val q = pageFilter.trim()
        if (q.isEmpty()) (1..Mushaf.TOTAL_PAGES).toList()
        else (1..Mushaf.TOTAL_PAGES).filter { p ->
            p.toString().contains(q) || p.toArabicDigits().contains(q)
        }
    }

    // Pre-compute the set of fully memorized surahs for the Golden Fihris seal
    val goldenSurahs: Set<Int> = remember(memorizedPages, surahPages) {
        (1..114).filter { s ->
            val start = surahPages[s] ?: return@filter false
            val end   = if (s < 114) (surahPages[s + 1] ?: (Mushaf.TOTAL_PAGES + 1)) - 1
            else Mushaf.TOTAL_PAGES
            start <= end && (start..end).all { it in memorizedPages }
        }.toSet()
    }

    // ── Page → primary-surah lookup ──────────────────────────────────────────
    //
    // The third tab (فهرس الصفحات) shows every one of the 604 Mushaf pages
    // with the primary surah on that page as context. "Primary" = the
    // last surah whose start page is ≤ the page. Surah start pages grow
    // monotonically across 1…114, so a single left-to-right scan per page
    // is enough; pre-computing once via `remember` keeps the 604 × 114
    // worst-case scan out of the recomposition path.
    val pageToSurah: IntArray = remember(surahPages) {
        val arr = IntArray(Mushaf.TOTAL_PAGES + 1) { 1 }
        for (p in 1..Mushaf.TOTAL_PAGES) {
            var primary = 1
            for (s in 1..114) {
                val start = surahPages[s] ?: continue
                if (start <= p) primary = s else break
            }
            arr[p] = primary
        }
        arr
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = theme.background) {
        // ── Three tabs: السور · الأجزاء · الصفحات ────────────────────────────
        //
        // Nasser 2026-04-21 asked for a فهرس الصفحات tab so students can
        // navigate by page reference (common in daily wird plans like
        // "pages 45-52 today"). Kept the label terse — "الصفحات" — to
        // sit visually alongside the two existing single-word tabs.
        TabRow(selectedTabIndex = tab, containerColor = theme.background, contentColor = theme.accent) {
            Tab(selected = tab == 0, onClick = { tab = 0 }) {
                Text("السور",    color = if (tab == 0) theme.accent else theme.text.copy(alpha = 0.5f), fontFamily = font.family, modifier = Modifier.padding(vertical = 12.dp))
            }
            Tab(selected = tab == 1, onClick = { tab = 1 }) {
                Text("الأجزاء", color = if (tab == 1) theme.accent else theme.text.copy(alpha = 0.5f), fontFamily = font.family, modifier = Modifier.padding(vertical = 12.dp))
            }
            Tab(selected = tab == 2, onClick = { tab = 2 }) {
                Text("الصفحات", color = if (tab == 2) theme.accent else theme.text.copy(alpha = 0.5f), fontFamily = font.family, modifier = Modifier.padding(vertical = 12.dp))
            }
        }
        // ── Filter row (Surah / Pages tabs only) ──────────────────────────────
        //
        // Sits just under the TabRow and above the list. Wrapped in a
        // LayoutDirection.Rtl composition-local so the placeholder anchors
        // to the visual right and the caret travels right-to-left as the
        // user types Arabic. Juz tab renders nothing here — see filter
        // rationale above.
        when (tab) {
            0 -> CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                OutlinedTextField(
                    value         = surahFilter,
                    onValueChange = { surahFilter = it },
                    placeholder   = {
                        Text(
                            "ابحث عن سورة…",
                            fontFamily = font.family,
                            style      = TextStyle(textDirection = TextDirection.Rtl)
                        )
                    },
                    singleLine    = true,
                    colors        = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor   = theme.accent,
                        unfocusedBorderColor = theme.accent.copy(alpha = 0.4f),
                        focusedTextColor     = theme.text,
                        unfocusedTextColor   = theme.text,
                        cursorColor          = theme.accent
                    ),
                    textStyle     = TextStyle(
                        textDirection = TextDirection.Rtl,
                        fontFamily    = font.family,
                        fontSize      = 14.sp
                    ),
                    modifier      = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
            2 -> CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                OutlinedTextField(
                    value         = pageFilter,
                    onValueChange = { pageFilter = it },
                    placeholder   = {
                        // FontFamily.Default — the Uthmanic font's
                        // digit→ayah-badge GSUB rule caps at 2 digits per
                        // glyph, so «٦٠٤» rendered as a 2-digit rosette
                        // plus a stray third digit (Nasser 2026-04-25).
                        // Same pattern that fixed the footer page badge.
                        Text(
                            "رقم الصفحة (١ – ٦٠٤)",
                            fontFamily = FontFamily.Default,
                            style      = TextStyle(textDirection = TextDirection.Rtl)
                        )
                    },
                    singleLine    = true,
                    colors        = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor   = theme.accent,
                        unfocusedBorderColor = theme.accent.copy(alpha = 0.4f),
                        focusedTextColor     = theme.text,
                        unfocusedTextColor   = theme.text,
                        cursorColor          = theme.accent
                    ),
                    textStyle     = TextStyle(
                        textDirection = TextDirection.Rtl,
                        fontFamily    = FontFamily.Default,
                        fontSize      = 14.sp
                    ),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier      = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
            else -> { /* Juz tab — no filter */ }
        }
        LazyColumn(modifier = Modifier.fillMaxWidth().height(if (tab == 1) 460.dp else 400.dp)) {
            when (tab) {
                0 -> {
                    if (filteredSurahs.isEmpty()) {
                        item {
                            Text(
                                "لا توجد سورة مطابقة",
                                color      = theme.text.copy(alpha = 0.6f),
                                fontSize   = 14.sp,
                                fontFamily = font.family,
                                modifier   = Modifier
                                    .fillMaxWidth()
                                    .padding(32.dp),
                                textAlign  = TextAlign.Center,
                                style      = TextStyle(textDirection = TextDirection.Rtl)
                            )
                        }
                    }
                    items(filteredSurahs) { n ->
                    val p       = surahPages[n] ?: 1
                    val isGold  = n in goldenSurahs
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (isGold) FIHRIS_GOLD_BG else theme.background)
                            .clickable { onNav(p) }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment     = Alignment.CenterVertically
                    ) {
                        // Left: page number
                        Text(
                            "ص ${p.toArabicDigits()}",
                            color    = if (isGold) FIHRIS_GOLD else theme.accent.copy(alpha = 0.7f),
                            fontSize = 13.sp
                        )
                        // Right: surah name + optional gold star seal
                        Row(
                            verticalAlignment     = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            // Surah number (1-114) prefix uses FontFamily.Default
                            // to sidestep Uthmanic digit→ayah-badge substitution,
                            // then the Arabic surah name is rendered right after.
                            // Rendering as two Text composables keeps the split
                            // clean and the name still reads in Uthmanic script.
                            Text(
                                "${n.toArabicDigits()}.",
                                color      = if (isGold) FIHRIS_GOLD else theme.text,
                                fontSize   = 15.sp,
                                fontFamily = FontFamily.Default,
                                fontWeight = if (isGold) FontWeight.Bold else FontWeight.Medium
                            )
                            Text(
                                MetadataParser.getSuraName(n),
                                color      = if (isGold) FIHRIS_GOLD else theme.text,
                                fontSize   = 15.sp,
                                fontFamily = font.family,
                                fontWeight = if (isGold) FontWeight.Bold else FontWeight.Medium,
                                style      = TextStyle(textDirection = TextDirection.Rtl)
                            )
                            if (isGold) {
                                Icon(
                                    Icons.Filled.Star, null,
                                    tint     = FIHRIS_GOLD,
                                    modifier = Modifier.size(14.dp)
                                )
                            }
                        }
                    }
                    HorizontalDivider(
                        color    = if (isGold) FIHRIS_GOLD.copy(alpha = 0.2f) else theme.divider,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                    }
                }
                1 -> items(30) { i ->
                    val n = i + 1; val p = juzPages[n] ?: 1
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable { onNav(p) }.padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment     = Alignment.CenterVertically
                    ) {
                        Text("ص ${p.toArabicDigits()}", color = theme.accent.copy(alpha = 0.7f), fontSize = 13.sp)
                        Text("الجزء ${n.toArabicDigits()}", color = theme.text, fontSize = 15.sp, fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, style = TextStyle(textDirection = TextDirection.Rtl))
                    }
                    HorizontalDivider(color = theme.divider, modifier = Modifier.padding(horizontal = 16.dp))
                }
                else -> {
                    if (filteredPages.isEmpty()) {
                        item {
                            Text(
                                "لا توجد صفحة مطابقة",
                                color      = theme.text.copy(alpha = 0.6f),
                                fontSize   = 14.sp,
                                fontFamily = font.family,
                                modifier   = Modifier
                                    .fillMaxWidth()
                                    .padding(32.dp),
                                textAlign  = TextAlign.Center,
                                style      = TextStyle(textDirection = TextDirection.Rtl)
                            )
                        }
                    }
                    items(filteredPages) { p ->
                        // Page index — "صفحة N" on the visual RIGHT (reading
                        // start in RTL) and the primary surah name on the
                        // visual LEFT as soft context. Tap a row to jump
                        // straight to that page.
                        val surah     = pageToSurah[p]
                        val surahName = MetadataParser.getSuraName(surah)
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable { onNav(p) }.padding(horizontal = 16.dp, vertical = 10.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment     = Alignment.CenterVertically
                        ) {
                            // Left: primary surah on that page (soft colour)
                            Text(
                                surahName,
                                color      = theme.accent.copy(alpha = 0.7f),
                                fontSize   = 13.sp,
                                fontFamily = font.family,
                                style      = TextStyle(textDirection = TextDirection.Rtl)
                            )
                            // Right: page identifier — "صفحة N"
                            Text(
                                "صفحة ${p.toArabicDigits()}",
                                color      = theme.text,
                                fontSize   = 15.sp,
                                fontFamily = FontFamily.Default,
                                fontWeight = FontWeight.Medium,
                                style      = TextStyle(textDirection = TextDirection.Rtl)
                            )
                        }
                        HorizontalDivider(color = theme.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    }
                }
            }
        }
    }
}

// =============================================================================
// Wird setup dialog
// =============================================================================

@Composable
private fun WirdDialog(
    page     : Int,
    prefs    : UserPreferences?,
    theme    : ThemeColors,
    onSet    : (ReadingTargetType, Int) -> Unit,
    onReset  : () -> Unit,
    onDismiss: () -> Unit
) {
    var type  by remember { mutableStateOf(ReadingTargetType.FINISH_IN_DAYS) }
    var value by remember { mutableStateOf("30") }
    AlertDialog(
        onDismissRequest  = onDismiss,
        containerColor    = theme.background,
        titleContentColor = theme.accent,
        textContentColor  = theme.text,
        title = {
            // Title matches the locked naming canon — see memory note
            // project_warattil_wird_requirements.  «إعداد الورد اليومي»
            // (set up the daily routine) reads as the action that opens
            // a multi-day plan; «اضبط ورد اليوم» (set today's reading)
            // misled readers into thinking the dialog was a one-day
            // configuration only.
            Text("إعداد الورد اليومي", fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(), style = TextStyle(textDirection = TextDirection.Rtl))
        },
        text = {
            // RTL wrapper — form fields and chip labels align right-to-left
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(
                            ReadingTargetType.FINISH_IN_DAYS to "بالأيام",
                            ReadingTargetType.PAGES_PER_DAY  to "بالصفحات",
                            ReadingTargetType.JUZ_PER_DAY    to "بالأجزاء"
                        ).forEach { (t, lbl) ->
                            FilterChip(
                                selected = type == t,
                                onClick  = {
                                    type  = t
                                    value = when (t) {
                                        ReadingTargetType.FINISH_IN_DAYS -> "30"
                                        ReadingTargetType.PAGES_PER_DAY  -> "20"
                                        else                             -> "1"
                                    }
                                },
                                label  = { Text(lbl, fontSize = 12.sp) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = theme.accent,
                                    selectedLabelColor     = theme.background
                                ),
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    // Input field — explicitly LTR so the number cursor behaves correctly,
                    // but the label text inherits RTL from the parent provider
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                        OutlinedTextField(
                            value         = value,
                            onValueChange = { if (it.all(Char::isDigit) && it.length <= 3) value = it },
                            label = {
                                Text(when (type) {
                                    ReadingTargetType.FINISH_IN_DAYS -> "عدد الأيام"
                                    ReadingTargetType.PAGES_PER_DAY  -> "صفحات يومياً"
                                    ReadingTargetType.JUZ_PER_DAY    -> "أجزاء يومياً"
                                })
                            },
                            singleLine  = true,
                            modifier    = Modifier.fillMaxWidth(),
                            colors      = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor   = theme.accent,
                                unfocusedBorderColor = theme.accent.copy(alpha = 0.4f),
                                focusedLabelColor    = theme.accent,
                                focusedTextColor     = theme.text,
                                unfocusedTextColor   = theme.text
                            ),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done)
                        )
                    } // end LTR number input
                    if (prefs?.wirdStartDate != null) {
                        Text(
                            "الورد الحالي: " + when (prefs.wirdTargetType) {
                                ReadingTargetType.FINISH_IN_DAYS -> "ختم في ${prefs.wirdTargetValue.toArabicDigits()} يوم"
                                ReadingTargetType.PAGES_PER_DAY  -> "${prefs.wirdTargetValue.toArabicDigits()} صفحة/يوم"
                                ReadingTargetType.JUZ_PER_DAY    -> "${prefs.wirdTargetValue.toArabicDigits()} جزء/يوم"
                            },
                            color = theme.text.copy(alpha = 0.6f), fontSize = 12.sp,
                            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                            style = TextStyle(textDirection = TextDirection.Rtl)
                        )
                    }
                }
            } // end RTL CompositionLocalProvider
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // Renamed 2026-04-27 (pt. 4): was «إيقاف الورد» — Nasser
                // wanted a positively-framed devotional alternative.
                // «ابدأ ختمة جديدة» reads as the start of a fresh khatma
                // rather than the cancellation of the current one — same
                // function (cancelWird clears wird state without touching
                // bookmarks / reading position) but the framing now
                // matches the user's intent when they reach for this
                // button (often after completing a cycle and wanting
                // to re-anchor the plan).
                TextButton(onClick = onReset) { Text("ابدأ ختمة جديدة", color = theme.accent) }
                Button(
                    onClick = { onSet(type, value.toIntOrNull()?.coerceAtLeast(1) ?: 1) },
                    colors  = ButtonDefaults.buttonColors(containerColor = theme.accent)
                ) { Text("ابدأ", color = theme.background) }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء", color = theme.text.copy(alpha = 0.6f)) }
        }
    )
}

// =============================================================================
// Bookmark sheet
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BookmarkSheet(
    bookmarks : List<com.warattil.app.data.Bookmark>,
    font      : QuranFontInfo,
    theme     : ThemeColors,
    onNav     : (Int) -> Unit,
    onDelete  : (Int) -> Unit,
    onClearAll: () -> Unit,
    onDismiss : () -> Unit
) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = theme.background) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment     = Alignment.CenterVertically
            ) {
                Text("إشاراتي", color = theme.accent, fontSize = 17.sp, fontWeight = FontWeight.Bold, fontFamily = font.family, style = TextStyle(textDirection = TextDirection.Rtl))
                if (bookmarks.isNotEmpty()) {
                    TextButton(onClick = onClearAll) { Text("حذف الكل", color = theme.progressLow, fontSize = 13.sp) }
                }
            }
            HorizontalDivider(color = theme.divider)

            if (bookmarks.isEmpty()) {
                Box(modifier = Modifier.fillMaxWidth().height(150.dp), contentAlignment = Alignment.Center) {
                    // Positive, action-oriented empty state — explains the next
                    // step instead of stating an absence.
                    Text("أضف أوّل إشارة لتعود إليها لاحقاً", color = theme.text.copy(alpha = 0.4f), fontFamily = font.family, style = TextStyle(textDirection = TextDirection.Rtl))
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp)) {
                    items(bookmarks, key = { it.pageNumber }) { bkm ->
                        val dismissState = rememberSwipeToDismissBoxState(
                            confirmValueChange = { v ->
                                if (v != SwipeToDismissBoxValue.Settled) { onDelete(bkm.pageNumber); true }
                                else false
                            }
                        )
                        SwipeToDismissBox(
                            state                       = dismissState,
                            enableDismissFromStartToEnd = false,
                            backgroundContent = {
                                Box(
                                    Modifier.fillMaxSize().background(theme.progressLow).padding(end = 20.dp),
                                    contentAlignment = Alignment.CenterEnd
                                ) { Icon(Icons.Filled.Delete, null, tint = theme.background) }
                            }
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(theme.background)
                                    .clickable { onNav(bkm.pageNumber) }
                                    .padding(horizontal = 12.dp, vertical = 12.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment     = Alignment.CenterVertically
                            ) {
                                IconButton(onClick = { onDelete(bkm.pageNumber) }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.Filled.Delete, "حذف", tint = theme.progressLow.copy(alpha = 0.7f), modifier = Modifier.size(16.dp))
                                }
                                Surface(color = theme.accent.copy(alpha = 0.12f), shape = RoundedCornerShape(6.dp)) {
                                    // FontFamily.Default — Uthmanic font splits
                                    // 3-digit page numbers into paired ayah-badge
                                    // glyphs; pages 100-604 hit this constantly.
                                    Text(
                                        bkm.pageNumber.toArabicDigits(),
                                        color = theme.accent, fontSize = 16.sp, fontWeight = FontWeight.Bold,
                                        fontFamily = FontFamily.Default, modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                                    )
                                }
                                Text("صفحة ${bkm.pageNumber.toArabicDigits()}", color = theme.text, fontSize = 15.sp, fontFamily = FontFamily.Default, style = TextStyle(textDirection = TextDirection.Rtl))
                            }
                        }
                        HorizontalDivider(color = theme.divider, modifier = Modifier.padding(horizontal = 12.dp))
                    }
                }
            }
            Spacer(Modifier.height(20.dp))
        }
    }
}

// =============================================================================
// Share-preview sheets (BLUEPRINT §11.4 + §11.7, April 2026)
//
// Two small bottom-sheet surfaces that mount their corresponding share card
// inside a `rememberGraphicsLayer` Box, so the user sees exactly what they're
// about to send.  A primary "مشاركة" button snapshots the layer to a Bitmap
// and hands it to the parent via [onShare].
//
// Design rationale
// ----------------
// V2 attempted a translate-offscreen + alpha-0 + drawWithContent approach so
// the cards could capture silently without a preview.  Two problems:
//   1. Compose occasionally skips the draw pass for offscreen children
//      (no visible tree → no draw invalidation), yielding blank bitmaps.
//   2. Users couldn't see what was about to be sent — in a Mushaf app the
//      consequences of sending a garbled card to a halaqa group are bad.
// The preview-sheet flow eliminates both failure modes: the capture tree is
// ALWAYS on-screen while the capture happens (no draw-skip), and the user
// gets a "see what you're about to share" beat before the system chooser.
//
// Mirrors V3's proven HifzLogSheet capture pattern exactly — single approach
// to bitmap capture across every share surface in the app.
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DailyReadingSharePreviewSheet(
    data     : DailyReadingCardData,
    font     : QuranFontInfo,
    theme    : ThemeColors,
    onShare  : (android.graphics.Bitmap) -> Unit,
    onDismiss: () -> Unit
) {
    val graphicsLayer = rememberGraphicsLayer()
    val scope         = rememberCoroutineScope()

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = theme.background) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Capturable region — the graphicsLayer records this Box's draw
            // output every frame it composes, so the snapshot is always
            // current when the share button fires.
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(theme.background)
                    .drawWithContent {
                        graphicsLayer.record { this@drawWithContent.drawContent() }
                        drawLayer(graphicsLayer)
                    }
            ) {
                DailyReadingShareCard(
                    data     = data,
                    theme    = theme,
                    font     = font,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(Modifier.height(14.dp))

            Button(
                onClick = {
                    scope.launch {
                        val bmp = graphicsLayer.toImageBitmap().asAndroidBitmap()
                        onShare(bmp)
                    }
                },
                colors = ButtonDefaults.buttonColors(
                    containerColor = theme.accent,
                    contentColor   = theme.background
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("مشاركة", fontFamily = font.family, fontSize = 15.sp)
            }

            Spacer(Modifier.height(8.dp))

            TextButton(
                onClick  = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    "إلغاء",
                    color      = theme.text.copy(alpha = 0.65f),
                    fontFamily = font.family,
                    fontSize   = 14.sp
                )
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppInviteSharePreviewSheet(
    font     : QuranFontInfo,
    theme    : ThemeColors,
    onShare  : (android.graphics.Bitmap) -> Unit,
    onDismiss: () -> Unit
) {
    val graphicsLayer = rememberGraphicsLayer()
    val scope         = rememberCoroutineScope()

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = theme.background) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // The invite card carries a 220 dp QR + tagline + hadith so the
            // sheet is taller than the daily card.  verticalScroll on the
            // outer Column keeps the primary button reachable on short
            // screens without clipping the card.
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(theme.background)
                    .drawWithContent {
                        graphicsLayer.record { this@drawWithContent.drawContent() }
                        drawLayer(graphicsLayer)
                    }
            ) {
                AppInviteShareCard(
                    theme    = theme,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(Modifier.height(14.dp))

            Button(
                onClick = {
                    scope.launch {
                        val bmp = graphicsLayer.toImageBitmap().asAndroidBitmap()
                        onShare(bmp)
                    }
                },
                colors = ButtonDefaults.buttonColors(
                    containerColor = theme.accent,
                    contentColor   = theme.background
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("مشاركة", fontFamily = font.family, fontSize = 15.sp)
            }

            Spacer(Modifier.height(8.dp))

            TextButton(
                onClick  = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    "إلغاء",
                    color      = theme.text.copy(alpha = 0.65f),
                    fontFamily = font.family,
                    fontSize   = 14.sp
                )
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}