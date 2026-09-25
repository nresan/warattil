//
//  HifzBulkPickerSheet.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/HifzBulkPickerSheet.kt to
//  SwiftUI.  See the Android file header for the full reader-model
//  explanation — the Swift port mirrors the Android semantics 1:1.
//
//  READER MENTAL MODEL (brief)
//  ---------------------------
//    "I'm editing the set of ayahs I have memorized.  Every tile shows the
//     truth *right now* (highlighted = in my memorized set).  I tap to add
//     or remove.  تثبيت commits the delta."
//
//  Implementation highlights:
//    • One shared `pendingKeys: Set<Int64>` drives all three tabs — juz,
//      surah, and a typed page-range.  Initial value is `initialMemorized`
//      so tiles open pre-selected rather than empty.
//    • Cross-tab state: selecting a juz fills its ayahs into pendingKeys,
//      which means flipping to the surah tab shows every surah inside that
//      juz pre-lit.
//    • Pages tab contributes via optimistic union — `effectivePending =
//      pendingKeys ∪ rangeKeys` is what tiles on juz / surah see.
//    • تثبيت emits (toAdd, toRemove) = (pending − initial, initial − pending).
//
//  Wire-format note: NO visibility modifiers on the call-site glue
//  because this is an internal Swift module — the Kotlin `public / private`
//  distinction collapses to file-private helpers at the bottom of the file.
//

import SwiftUI

// =============================================================================
// MARK: Public sheet
// =============================================================================

struct HifzBulkPickerSheet: View {

    // Inputs
    let initialMemorized: Set<Int64>
    let font:             QuranFontInfo
    let theme:            ThemeColors
    let onApply:          (_ toAdd: Set<Int64>, _ toRemove: Set<Int64>) -> Void
    let onDismiss:        () -> Void

    // Unified pending set — snapshotted from `initialMemorized` once,
    // survives tab switches.  Local @State so background updates to the
    // caller's set don't clobber the user's in-progress edits (matches
    // Android's deliberate choice not to key the remember on
    // initialMemorized).
    @State private var pendingKeys: Set<Int64> = []

    // Pages-tab typed range — Eastern OR Western digits accepted.
    @State private var fromPageText: String = ""
    @State private var toPageText:   String = ""

    // Active tab (0 = juz, 1 = surah, 2 = pages).
    @State private var tab: Int = 0

    // Focus target for the page-range fields so dismissing the sheet
    // also dismisses the keyboard.
    private enum PageField { case from, to }
    @FocusState private var focusedField: PageField?

    /// Derived — the set juz/surah tiles see.  Optimistically unions the
    /// parsed page range into pendingKeys so typing a range on the pages
    /// tab lights up juz tiles elsewhere.
    private var effectivePending: Set<Int64> {
        let range = Self.computePageRangeKeys(from: fromPageText, to: toPageText)
        if range.isEmpty { return pendingKeys }
        return pendingKeys.union(range)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Title ─────────────────────────────────────────────────────
            Text("تسجيل ما تحفظه")
                .font(.warattilChrome(size: 18, weight: .bold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            // ── Hint strip ────────────────────────────────────────────────
            Text("المختار هو ما تحفظه · اضغط لتعليم أو مسح")
                .font(.warattilChrome(size: 11))
                .foregroundStyle(theme.text.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 8)

            // ── Tab row ───────────────────────────────────────────────────
            tabRow
                .padding(.horizontal, 12)

            // ── Tab content — fixed height so apply-footer position is stable
            ZStack {
                switch tab {
                case 0:  juzGrid
                case 1:  surahGrid
                default: pageRangeForm
                }
            }
            .frame(height: 380)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // ── Footer — delta summary + apply button ─────────────────────
            bulkFooter
        }
        .background(theme.background)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            // Snapshot the initial set once.  Also seed the pages-tab
            // range with the longest contiguous fully-memorized run so
            // an existing-hifz user sees their current plan pre-filled.
            if pendingKeys.isEmpty {
                pendingKeys = initialMemorized
            }
            if fromPageText.isEmpty && toPageText.isEmpty {
                let (lo, hi) = Self.longestContiguousMemorizedRun(initialMemorized)
                fromPageText = lo.map { $0.arabicDigits } ?? ""
                toPageText   = hi.map { $0.arabicDigits } ?? ""
            }
        }
    }

    // =========================================================================
    // MARK: Tab row
    // =========================================================================

    private var tabRow: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, label: "أجزاء")
            tabButton(index: 1, label: "سور")
            tabButton(index: 2, label: "نطاق صفحات")
        }
        .background(
            Rectangle()
                .fill(theme.divider.opacity(0.5))
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }

    private func tabButton(index: Int, label: String) -> some View {
        let active = (tab == index)
        return Button(action: { tab = index }) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.warattilChrome(size: 14, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? WarattilConstants.Hifz.hifzGold
                                            : theme.text.opacity(0.5))
                Rectangle()
                    .fill(active ? WarattilConstants.Hifz.hifzGold : Color.clear)
                    .frame(height: 2)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // =========================================================================
    // MARK: Juz grid — 1..30, 6 columns
    // =========================================================================

    private var juzGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
        let eff = effectivePending
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(1...WarattilConstants.Mushaf.totalJuzaa, id: \.self) { j in
                    let keys = MetadataParser.shared.getJuzAyahKeys(j)
                    let isOn = !keys.isEmpty && keys.allSatisfy { eff.contains($0) }
                    PickerCell(
                        primary:   j.arabicDigits,
                        secondary: "جزء",
                        isOn:      isOn,
                        theme:     theme
                    ) {
                        pendingKeys = Self.toggleUnit(pendingKeys, unitKeys: keys)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // =========================================================================
    // MARK: Surah grid — 1..114, 4 columns (name room)
    // =========================================================================

    private var surahGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        let eff = effectivePending
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(1...WarattilConstants.Mushaf.totalSuwar, id: \.self) { s in
                    let keys = MetadataParser.shared.getSurahAyahKeys(s)
                    let isOn = !keys.isEmpty && keys.allSatisfy { eff.contains($0) }
                    let name = MetadataParser.shared.getSuraName(s)
                    PickerCell(
                        primary:   name.isEmpty ? s.arabicDigits : name,
                        secondary: s.arabicDigits,
                        isOn:      isOn,
                        theme:     theme
                    ) {
                        pendingKeys = Self.toggleUnit(pendingKeys, unitKeys: keys)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // =========================================================================
    // MARK: Page-range form
    // =========================================================================

    private var pageRangeForm: some View {
        VStack(spacing: 16) {
            Text("أدخل نطاق الصفحات المحفوظة")
                .font(.warattilChrome(size: 13))
                .foregroundStyle(theme.text.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            HStack(spacing: 12) {
                TextField("من", text: $fromPageText)
                    .environment(\.layoutDirection, .leftToRight)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .from)
                    .warattilTextField(theme: theme)
                    .onChange(of: fromPageText) { _, newValue in
                        fromPageText = Self.sanitizePageInput(newValue)
                    }

                TextField("إلى", text: $toPageText)
                    .environment(\.layoutDirection, .leftToRight)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .to)
                    .warattilTextField(theme: theme)
                    .onChange(of: toPageText) { _, newValue in
                        toPageText = Self.sanitizePageInput(newValue)
                    }
            }

            Text("الصفحات من \(1.arabicDigits) إلى \(WarattilConstants.Mushaf.totalPages.arabicDigits)")
                .font(.warattilChrome(size: 11))
                .foregroundStyle(theme.text.opacity(0.5))

            Text("سيتم ضم هذا النطاق إلى اختيارك في التبويبات الأخرى")
                .font(.warattilChrome(size: 10))
                .foregroundStyle(theme.text.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // =========================================================================
    // MARK: Footer
    // =========================================================================

    private var bulkFooter: some View {
        let eff = effectivePending
        let toAdd    = eff.subtracting(initialMemorized)
        let toRemove = initialMemorized.subtracting(eff)
        let hasChange = !toAdd.isEmpty || !toRemove.isEmpty

        let summary: String = {
            if !hasChange {
                return "لا تغيير · \(eff.count.arabicDigits) آية محفوظة"
            }
            if !toAdd.isEmpty && !toRemove.isEmpty {
                return "+\(toAdd.count.arabicDigits) آية · −\(toRemove.count.arabicDigits) آية"
            }
            if !toAdd.isEmpty {
                return "+\(toAdd.count.arabicDigits) آية جديدة"
            }
            return "−\(toRemove.count.arabicDigits) آية"
        }()

        return VStack(spacing: 10) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 0.5)

            HStack {
                Text(summary)
                    .font(.warattilChrome(size: 13))
                    .foregroundStyle(theme.text.opacity(0.7))
                Spacer()
                Button(action: {
                    onApply(toAdd, toRemove)
                }) {
                    Text("تثبيت")
                        .font(.warattilChrome(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(hasChange
                                      ? WarattilConstants.Hifz.hifzGold
                                      : WarattilConstants.Hifz.hifzGold.opacity(0.25))
                        )
                }
                .disabled(!hasChange)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // =========================================================================
    // MARK: Static helpers — pure functions, mirror the Android fileprivate fns
    // =========================================================================

    /// Toggle a unit (juz/surah) in pendingKeys.  If every ayah of the unit
    /// is already in the set, remove them all (deselect); otherwise add
    /// every ayah (fill in any missing).  Matches the tile's `isOn` rule
    /// (isOn ⟺ full containment) so one tap always flips the visible state.
    static func toggleUnit(_ pendingKeys: Set<Int64>, unitKeys: [Int64]) -> Set<Int64> {
        if unitKeys.isEmpty { return pendingKeys }
        var next = pendingKeys
        let allIn = unitKeys.allSatisfy { next.contains($0) }
        if allIn {
            for k in unitKeys { next.remove(k) }
        } else {
            for k in unitKeys { next.insert(k) }
        }
        return next
    }

    /// Parse (from, to) page numbers — Eastern-Arabic (٠-٩) or ASCII —
    /// and expand to the set of ayah keys inclusive.  Returns an empty
    /// set if either field is blank or unparseable.
    static func computePageRangeKeys(from: String, to: String) -> Set<Int64> {
        guard let a = parsePageInput(from),
              let b = parsePageInput(to) else { return [] }
        let lo = min(max(min(a, b), 1), WarattilConstants.Mushaf.totalPages)
        let hi = min(max(max(a, b), 1), WarattilConstants.Mushaf.totalPages)
        var out = Set<Int64>()
        out.reserveCapacity((hi - lo + 1) * 10)
        for p in lo...hi {
            for k in MetadataParser.shared.getPageAyahKeys(p) {
                out.insert(k)
            }
        }
        return out
    }

    /// Longest run of consecutive fully-memorized pages in `memorized`.
    /// Returns (start, end) or (nil, nil).
    static func longestContiguousMemorizedRun(_ memorized: Set<Int64>) -> (Int?, Int?) {
        if memorized.isEmpty { return (nil, nil) }
        var bestStart = 0
        var bestEnd   = 0
        var curStart  = 0
        for p in 1...WarattilConstants.Mushaf.totalPages {
            let keys = MetadataParser.shared.getPageAyahKeys(p)
            let full = !keys.isEmpty && keys.allSatisfy { memorized.contains($0) }
            if full {
                if curStart == 0 { curStart = p }
                if p - curStart > bestEnd - bestStart {
                    bestStart = curStart
                    bestEnd   = p
                }
            } else {
                curStart = 0
            }
        }
        return bestStart == 0 ? (nil, nil) : (bestStart, bestEnd)
    }

    /// Sanitize a page-input TextField value: keep only digits (ASCII or
    /// Eastern-Arabic) and cap at 3 characters so a typo can't produce
    /// a ludicrous page like "9999".
    static func sanitizePageInput(_ raw: String) -> String {
        let filtered = raw.unicodeScalars.filter { scalar -> Bool in
            let v = scalar.value
            return (v >= 0x30 && v <= 0x39)      // ASCII digits
                || (v >= 0x0660 && v <= 0x0669)  // Eastern-Arabic-Indic digits
        }
        return String(String.UnicodeScalarView(filtered.prefix(3)))
    }

    /// Parse a page-input String (Eastern-Arabic or ASCII digits) into
    /// an Int, or nil if the string is blank or contains a non-digit.
    static func parsePageInput(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        var builder = ""
        for ch in trimmed.unicodeScalars {
            let v = ch.value
            if v >= 0x30 && v <= 0x39 {
                builder.append(Character(ch))
            } else if v >= 0x0660 && v <= 0x0669 {
                let asciiScalar = Unicode.Scalar(0x30 + (v - 0x0660))!
                builder.append(Character(asciiScalar))
            } else {
                return nil
            }
        }
        return Int(builder)
    }
}

// =============================================================================
// MARK: PickerCell — shared selectable tile (juz / surah)
// =============================================================================

private struct PickerCell: View {
    let primary:   String
    let secondary: String
    let isOn:      Bool
    let theme:     ThemeColors
    let onClick:   () -> Void

    var body: some View {
        let bg     = isOn ? WarattilConstants.Hifz.hifzGold.opacity(0.18) : theme.background
        let border = isOn ? WarattilConstants.Hifz.hifzGold : theme.divider
        let fg     = isOn ? WarattilConstants.Hifz.hifzGold : theme.text

        Button(action: onClick) {
            ZStack {
                VStack(spacing: 1) {
                    Text(primary)
                        .font(.warattilChrome(size: 14, weight: isOn ? .bold : .regular))
                        .foregroundStyle(fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(secondary)
                        .font(.system(size: 10))
                        .foregroundStyle(fg.opacity(0.55))
                }
                .padding(.horizontal, 4)

                if isOn {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
                                .padding(4)
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(border, lineWidth: isOn ? 1.25 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
