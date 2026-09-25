package com.warattil.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.core.WarattilConstants.Hifz
import com.warattil.app.core.WarattilConstants.Mushaf
import com.warattil.app.data.MetadataParser

// =============================================================================
// HifzBulkPickerSheet — unified pending-set model (Phase 1.2)
//
// Reader mental model:
//   "I'm editing the set of ayahs I have memorized.  Every tile shows the
//    truth *right now* (highlighted = in my memorized set).  I tap to add
//    or remove.  تثبيت commits the delta."
//
// Implementation:
//   One shared `pendingKeys: Set<Long>` drives all three tabs.  Initial value
//   is the caller's `initialMemorized`, so tiles open already reflecting what
//   the user has — solving the "all tiles empty on open" bug.  Selecting a
//   full juz on the juz tab puts its ayahs into pendingKeys, which means
//   flipping to the surah tab shows every surah contained in that juz as
//   already-selected — the cross-tab propagation the user asked for.
//
// The pages tab is slightly special: it's a typed from..to range rather than
// a tile grid, so it contributes to pendingKeys via an *optimistic* union.
// As soon as both fields parse, `effectivePending = pendingKeys ∪ rangeKeys`
// is what juz/surah tiles see.  This keeps the tab genuinely unified rather
// than siloed, at the cost of a slight subtlety: until the user types a
// valid range, the pages tab has no effect on the other tabs.  That's fine.
//
// Pre-fill for pages tab: longest contiguous run of fully-memorized pages.
// If the user has pages 12..40 memorized continuously plus page 80 alone,
// the inputs open with "12" and "40".  They can adjust from there or
// overwrite entirely.  Empty if no memorization yet.
//
// Apply:
//   emits (toAdd, toRemove) = (effectivePending − initialMemorized,
//                              initialMemorized − effectivePending).
//   Either or both may be empty; the ViewModel call site fires each
//   non-empty side as its own setAyahsMemorized(...) write.
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HifzBulkPickerSheet(
    initialMemorized: Set<Long>,
    surahNames      : (Int) -> String,
    font            : QuranFontInfo,
    theme           : ThemeColors,
    onApply         : (toAdd: Set<Long>, toRemove: Set<Long>) -> Unit,
    onDismiss       : () -> Unit
) {
    var tab by remember { mutableIntStateOf(0) }

    // ── Unified pending set ───────────────────────────────────────────────────
    //   Snapshot of the caller's set captured ONCE at sheet-open time.  We
    //   deliberately do not key on `initialMemorized` — if a background
    //   update (widget, worker) changes memorizedAyahs while the sheet is
    //   open, we keep the user's in-progress edits.  Clicking تثبيت then
    //   applies their diff against the fresh baseline, which may include
    //   or exclude the background change — but that's a rare race with no
    //   clean semantics either way; not blowing away the user's edits is
    //   the friendlier default.
    var pendingKeys by remember { mutableStateOf(initialMemorized.toSet()) }

    // ── Pages tab: typed from..to range, pre-filled with longest contiguous
    //              fully-memorized run (can be empty) ───────────────────────────
    val (initFrom, initTo) = remember { longestContiguousMemorizedRun(initialMemorized) }
    var fromPageText by remember { mutableStateOf(initFrom?.toArabicDigits() ?: "") }
    var toPageText   by remember { mutableStateOf(initTo?.toArabicDigits()   ?: "") }

    // Optimistic union: pages tab's typed range contributes to what juz/surah
    // tiles consider "already in" — so typing a range on the pages tab lights
    // up juz tiles elsewhere (cross-tab propagation in the opposite direction).
    val effectivePending: Set<Long> = remember(pendingKeys, fromPageText, toPageText) {
        val rangeKeys = computePageRangeKeys(fromPageText, toPageText)
        if (rangeKeys.isEmpty()) pendingKeys else pendingKeys + rangeKeys
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor   = theme.background
    ) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            Column(modifier = Modifier.fillMaxWidth()) {

                // ── Title ─────────────────────────────────────────────────────
                Text(
                    "تسجيل ما تحفظه",
                    color      = Hifz.HIFZ_GOLD,
                    fontSize   = 18.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = font.family,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, bottom = 2.dp)
                )

                // ── Hint strip — explains the unified model briefly ──────────
                Text(
                    "المختار هو ما تحفظه · اضغط لتعليم أو مسح",
                    color      = theme.text.copy(alpha = 0.55f),
                    fontSize   = 11.sp,
                    fontFamily = font.family,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 6.dp)
                )

                // ── Tab row ───────────────────────────────────────────────────
                TabRow(
                    selectedTabIndex = tab,
                    containerColor   = theme.background,
                    contentColor     = Hifz.HIFZ_GOLD
                ) {
                    Tab(selected = tab == 0, onClick = { tab = 0 }) {
                        Text(
                            "أجزاء",
                            color    = if (tab == 0) Hifz.HIFZ_GOLD else theme.text.copy(alpha = 0.5f),
                            fontFamily = font.family,
                            modifier = Modifier.padding(vertical = 12.dp)
                        )
                    }
                    Tab(selected = tab == 1, onClick = { tab = 1 }) {
                        Text(
                            "سور",
                            color    = if (tab == 1) Hifz.HIFZ_GOLD else theme.text.copy(alpha = 0.5f),
                            fontFamily = font.family,
                            modifier = Modifier.padding(vertical = 12.dp)
                        )
                    }
                    Tab(selected = tab == 2, onClick = { tab = 2 }) {
                        Text(
                            "نطاق صفحات",
                            color    = if (tab == 2) Hifz.HIFZ_GOLD else theme.text.copy(alpha = 0.5f),
                            fontFamily = font.family,
                            modifier = Modifier.padding(vertical = 12.dp)
                        )
                    }
                }

                // ── Tab content ───────────────────────────────────────────────
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(380.dp)
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    when (tab) {
                        0 -> JuzGrid(
                            pendingKeys  = effectivePending,
                            font         = font,
                            theme        = theme,
                            onToggle     = { juz ->
                                pendingKeys = toggleUnit(
                                    pendingKeys,
                                    MetadataParser.getJuzAyahKeys(juz)
                                )
                            }
                        )
                        1 -> SurahGrid(
                            pendingKeys = effectivePending,
                            surahNames  = surahNames,
                            font        = font,
                            theme       = theme,
                            onToggle    = { surah ->
                                pendingKeys = toggleUnit(
                                    pendingKeys,
                                    MetadataParser.getSurahAyahKeys(surah)
                                )
                            }
                        )
                        2 -> PageRangeForm(
                            fromText = fromPageText,
                            toText   = toPageText,
                            onFromChanged = { fromPageText = it },
                            onToChanged   = { toPageText   = it },
                            font  = font,
                            theme = theme
                        )
                    }
                }

                // ── Summary + apply ───────────────────────────────────────────
                //   The apply callback owns lifecycle: caller decides whether
                //   to close the sheet, re-open the Hifz log on the heatmap
                //   tab, etc.  We only pass the delta up — no implicit
                //   dismissal here — so a "cancel" (swipe-down / tap-outside)
                //   and an "apply" stay cleanly separated paths.
                BulkFooter(
                    initialMemorized = initialMemorized,
                    effectivePending = effectivePending,
                    font             = font,
                    theme            = theme,
                    onApply          = { toAdd, toRemove ->
                        onApply(toAdd, toRemove)
                    }
                )
            }
        }
    }
}

// =============================================================================
// Juz grid — 1..30, 6 columns, pre-selected from pendingKeys membership
// =============================================================================

@Composable
private fun JuzGrid(
    pendingKeys : Set<Long>,
    font        : QuranFontInfo,
    theme       : ThemeColors,
    onToggle    : (Int) -> Unit
) {
    val juzNumbers = remember { (1..Mushaf.TOTAL_JUZAA).toList() }
    LazyVerticalGrid(
        columns               = GridCells.Fixed(6),
        modifier              = Modifier.fillMaxSize(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement   = Arrangement.spacedBy(6.dp)
    ) {
        items(juzNumbers) { j ->
            val keys = remember(j) { MetadataParser.getJuzAyahKeys(j) }
            val isOn = keys.isNotEmpty() && keys.all { it in pendingKeys }
            PickerCell(
                primary   = j.toArabicDigits(),
                secondary = "جزء",
                isOn      = isOn,
                font      = font,
                theme     = theme,
                onClick   = { onToggle(j) }
            )
        }
    }
}

// =============================================================================
// Surah grid — 1..114, 4 columns (name room), pre-selected from pendingKeys
// =============================================================================

@Composable
private fun SurahGrid(
    pendingKeys : Set<Long>,
    surahNames  : (Int) -> String,
    font        : QuranFontInfo,
    theme       : ThemeColors,
    onToggle    : (Int) -> Unit
) {
    val suraNumbers = remember { (1..Mushaf.TOTAL_SUWAR).toList() }
    LazyVerticalGrid(
        columns               = GridCells.Fixed(4),
        modifier              = Modifier.fillMaxSize(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement   = Arrangement.spacedBy(6.dp)
    ) {
        items(suraNumbers) { s ->
            val keys = remember(s) { MetadataParser.getSurahAyahKeys(s) }
            val isOn = keys.isNotEmpty() && keys.all { it in pendingKeys }
            PickerCell(
                primary   = surahNames(s).takeIf { it.isNotBlank() } ?: s.toArabicDigits(),
                secondary = s.toArabicDigits(),
                isOn      = isOn,
                font      = font,
                theme     = theme,
                onClick   = { onToggle(s) }
            )
        }
    }
}

// =============================================================================
// Shared selectable tile
// =============================================================================

@Composable
private fun PickerCell(
    primary   : String,
    secondary : String,
    isOn      : Boolean,
    font      : QuranFontInfo,
    theme     : ThemeColors,
    onClick   : () -> Unit
) {
    val bg = if (isOn) Hifz.HIFZ_GOLD.copy(alpha = 0.18f) else theme.background
    val border = if (isOn) Hifz.HIFZ_GOLD else theme.divider
    val fg = if (isOn) Hifz.HIFZ_GOLD else theme.text

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(bg)
            .border(
                width = if (isOn) 1.25.dp else 0.5.dp,
                color = border,
                shape = RoundedCornerShape(8.dp)
            )
            .clickable(onClick = onClick)
    ) {
        Column(
            modifier              = Modifier.align(Alignment.Center).padding(horizontal = 4.dp),
            horizontalAlignment   = Alignment.CenterHorizontally,
            verticalArrangement   = Arrangement.Center
        ) {
            Text(
                primary,
                color      = fg,
                fontSize   = 14.sp,
                fontWeight = if (isOn) FontWeight.Bold else FontWeight.Normal,
                fontFamily = font.family,
                maxLines   = 1
            )
            Text(
                secondary,
                color      = fg.copy(alpha = 0.55f),
                fontSize   = 10.sp,
                fontFamily = FontFamily.Default
            )
        }
        if (isOn) {
            Icon(
                Icons.Filled.Check, null,
                tint     = Hifz.HIFZ_GOLD,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(4.dp)
                    .size(14.dp)
            )
        }
    }
}

// =============================================================================
// Page-range form — two numeric inputs, Eastern-or-Western digits accepted
// =============================================================================

@Composable
private fun PageRangeForm(
    fromText     : String,
    toText       : String,
    onFromChanged: (String) -> Unit,
    onToChanged  : (String) -> Unit,
    font         : QuranFontInfo,
    theme        : ThemeColors
) {
    Column(
        modifier              = Modifier.fillMaxSize(),
        horizontalAlignment   = Alignment.CenterHorizontally,
        verticalArrangement   = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            "أدخل نطاق الصفحات المحفوظة",
            color      = theme.text.copy(alpha = 0.7f),
            fontSize   = 13.sp,
            fontFamily = font.family,
            textAlign  = TextAlign.Center,
            modifier   = Modifier.padding(top = 8.dp)
        )

        Row(
            modifier              = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment     = Alignment.CenterVertically
        ) {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                OutlinedTextField(
                    value         = fromText,
                    onValueChange = { raw -> onFromChanged(raw.filter(::isAsciiOrArabicDigit).take(3)) },
                    label         = { Text("من", fontFamily = font.family) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine    = true,
                    modifier      = Modifier.weight(1f),
                    colors        = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor   = Hifz.HIFZ_GOLD,
                        unfocusedBorderColor = theme.divider,
                        focusedLabelColor    = Hifz.HIFZ_GOLD,
                        unfocusedLabelColor  = theme.text.copy(alpha = 0.6f),
                        cursorColor          = Hifz.HIFZ_GOLD,
                        focusedTextColor     = theme.text,
                        unfocusedTextColor   = theme.text
                    )
                )
                OutlinedTextField(
                    value         = toText,
                    onValueChange = { raw -> onToChanged(raw.filter(::isAsciiOrArabicDigit).take(3)) },
                    label         = { Text("إلى", fontFamily = font.family) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine    = true,
                    modifier      = Modifier.weight(1f),
                    colors        = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor   = Hifz.HIFZ_GOLD,
                        unfocusedBorderColor = theme.divider,
                        focusedLabelColor    = Hifz.HIFZ_GOLD,
                        unfocusedLabelColor  = theme.text.copy(alpha = 0.6f),
                        cursorColor          = Hifz.HIFZ_GOLD,
                        focusedTextColor     = theme.text,
                        unfocusedTextColor   = theme.text
                    )
                )
            }
        }

        Text(
            "الصفحات من ${1.toArabicDigits()} إلى ${Mushaf.TOTAL_PAGES.toArabicDigits()}",
            color      = theme.text.copy(alpha = 0.5f),
            fontSize   = 11.sp,
            fontFamily = font.family
        )

        Text(
            "سيتم ضم هذا النطاق إلى اختيارك في التبويبات الأخرى",
            color      = theme.text.copy(alpha = 0.45f),
            fontSize   = 10.sp,
            fontFamily = font.family,
            textAlign  = TextAlign.Center,
            modifier   = Modifier.padding(horizontal = 12.dp)
        )
    }
}

// =============================================================================
// Footer — delta summary + apply button
// =============================================================================

@Composable
private fun BulkFooter(
    initialMemorized : Set<Long>,
    effectivePending : Set<Long>,
    font             : QuranFontInfo,
    theme            : ThemeColors,
    onApply          : (toAdd: Set<Long>, toRemove: Set<Long>) -> Unit
) {
    val toAdd    = remember(initialMemorized, effectivePending) { effectivePending - initialMemorized }
    val toRemove = remember(initialMemorized, effectivePending) { initialMemorized - effectivePending }

    val hasChange = toAdd.isNotEmpty() || toRemove.isNotEmpty()

    val summary = when {
        !hasChange          -> "لا تغيير · ${effectivePending.size.toArabicDigits()} آية محفوظة"
        toAdd.isNotEmpty() && toRemove.isNotEmpty() ->
            "+${toAdd.size.toArabicDigits()} آية · −${toRemove.size.toArabicDigits()} آية"
        toAdd.isNotEmpty()  -> "+${toAdd.size.toArabicDigits()} آية جديدة"
        else                -> "−${toRemove.size.toArabicDigits()} آية"
    }

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        HorizontalDivider(color = theme.divider, thickness = 0.5.dp)
        Spacer(Modifier.height(10.dp))
        Row(
            modifier              = Modifier.fillMaxWidth(),
            verticalAlignment     = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                summary,
                color      = theme.text.copy(alpha = 0.7f),
                fontSize   = 13.sp,
                fontFamily = font.family
            )
            Button(
                onClick  = { onApply(toAdd, toRemove) },
                enabled  = hasChange,
                colors   = ButtonDefaults.buttonColors(
                    containerColor = Hifz.HIFZ_GOLD,
                    contentColor   = Color.White,
                    disabledContainerColor = Hifz.HIFZ_GOLD.copy(alpha = 0.25f),
                    disabledContentColor   = Color.White.copy(alpha = 0.5f)
                ),
                shape    = RoundedCornerShape(10.dp)
            ) {
                Text(
                    "تثبيت",
                    fontFamily = font.family,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

// =============================================================================
// Private helpers
// =============================================================================

/**
 * Toggle a unit (juz/surah) in pendingKeys.  Semantics: if ALL of the unit's
 * ayahs are already in the set, remove them (deselect the unit entirely);
 * otherwise add all of them (fill in any missing ayahs).
 *
 * Matches the tile's isOn rule: isOn ⟺ full containment, so a single tap
 * always moves the tile to the opposite visual state.
 */
private fun toggleUnit(pendingKeys: Set<Long>, unitKeys: List<Long>): Set<Long> {
    if (unitKeys.isEmpty()) return pendingKeys
    val allIn = unitKeys.all { it in pendingKeys }
    val next = pendingKeys.toHashSet()
    if (allIn) next.removeAll(unitKeys.toSet())
    else       next.addAll(unitKeys)
    return next
}

/** Parse a from/to text pair into a set of ayah keys, or empty if either
 *  field is unparseable.  Page numbers are coerced into 1..604.  Accepts
 *  Eastern-Arabic digits (٠-٩) or ASCII. */
private fun computePageRangeKeys(fromText: String, toText: String): Set<Long> {
    val from = parsePageInput(fromText) ?: return emptySet()
    val to   = parsePageInput(toText)   ?: return emptySet()
    val lo = minOf(from, to).coerceIn(1, Mushaf.TOTAL_PAGES)
    val hi = maxOf(from, to).coerceIn(1, Mushaf.TOTAL_PAGES)
    val out = HashSet<Long>((hi - lo + 1) * 10)
    for (p in lo..hi) out.addAll(MetadataParser.getPageAyahKeys(p))
    return out
}

/**
 * Longest run of consecutive fully-memorized pages in the user's current set.
 * Returns (startPage, endPage) or (null, null) if no pages are fully
 * memorized yet.
 *
 * Used to pre-fill the pages tab so a user who has pages 1..50 done sees
 * "1" and "50" already in the inputs when they open the sheet — a tap on
 * تثبيت would then be a no-op (no delta), which is correct.
 */
private fun longestContiguousMemorizedRun(memorized: Set<Long>): Pair<Int?, Int?> {
    if (memorized.isEmpty()) return null to null
    var bestStart = 0
    var bestEnd   = 0
    var curStart  = 0
    for (p in 1..Mushaf.TOTAL_PAGES) {
        val keys = MetadataParser.getPageAyahKeys(p)
        val full = keys.isNotEmpty() && keys.all { it in memorized }
        if (full) {
            if (curStart == 0) curStart = p
            // Update best on every step while the run continues
            if (p - curStart > bestEnd - bestStart) {
                bestStart = curStart
                bestEnd   = p
            }
        } else {
            curStart = 0
        }
    }
    return if (bestStart == 0) null to null else bestStart to bestEnd
}

private fun isAsciiOrArabicDigit(ch: Char): Boolean =
    ch in '0'..'9' || ch in '٠'..'٩'

private fun parsePageInput(text: String): Int? {
    if (text.isBlank()) return null
    val normalized = buildString(text.length) {
        for (ch in text) {
            when (ch) {
                in '0'..'9' -> append(ch)
                in '٠'..'٩' -> append(('0'.code + (ch.code - '٠'.code)).toChar())
                else -> return null
            }
        }
    }
    return normalized.toIntOrNull()
}
