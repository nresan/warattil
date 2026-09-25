//
//  MushaFViewModelTests.swift
//  WarattilTests
//
//  Unit tests for the Wird Momentum Engine — pure tier math on top of
//  UserPreferences state. No UI, no real page loads.
//
//  Why these tests matter:
//    The footer shows the user a single colored progress bar and a one-line
//    Arabic status message. If a tier boundary is off by one, the user sees
//    the WRONG encouragement or worse — they see "goal completed" when they
//    haven't yet. Subtle bug, high trust cost. These tests lock the exact
//    Kotlin tier boundaries into Swift.
//
//  What we cover:
//    - wirdDailyPages() for all three ReadingTargetType values (incl. the
//      "at least 1" coercion on zero/negative inputs)
//    - wirdProgressRatio() both with AND without a configured wird
//    - wirdProgressColor() tier boundaries (0.30, 0.70, 1.00)
//    - wirdProgressMessage() wording for every tier, wird-active + fallback
//
//  What we do NOT cover here:
//    - Page loading (covered by QuranRepositoryTests + live-fire on device)
//    - Theme cycling (trivial 3-state rotation)
//    - UserDefaults persistence (integration concern; we stub defaults in setUp)
//

import XCTest
import SwiftUI
@testable import Warattil

@MainActor
final class MushaFViewModelTests: XCTestCase {

    private var vm: MushaFViewModel!

    // A per-test ephemeral UserDefaults so we don't clobber the real app's
    // persisted state and so each test starts from a pristine slate.
    private var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()

        // Momentum engine is pure math but MushaFViewModel still insists on a
        // live QuranRepository in init — open the real DB once, like
        // QuranRepositoryTests does. Fast (bundled DB is ~15MB).
        MetadataParser.shared.__resetForTesting()
        try MetadataParser.shared.load(bundle: Bundle.main)
        try QuranDatabase.shared.open()

        // Use a namespaced suite so test writes never touch the real app's
        // last-read page / theme ordinal on the simulator.
        let suiteName = "WarattilTests.MushaFViewModelTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        // Fresh slate — overwrite any pre-existing values (shouldn't be any
        // given the UUID suite, but belt-and-suspenders).
        testDefaults.removePersistentDomain(forName: suiteName)

        vm = MushaFViewModel(
            repository: try QuranRepository(),
            defaults:   testDefaults
        )
    }

    override func tearDown() async throws {
        vm = nil
        testDefaults = nil
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: wirdDailyPages — daily goal derivation
    // =========================================================================

    /// PAGES_PER_DAY is the simplest — returns the value verbatim, with a
    /// "never less than 1" coercion for defensive input handling.
    func testDailyPages_pagesPerDay_returnsVerbatim() {
        let p = makePrefs(type: .pagesPerDay, value: 5, startPage: 1)
        XCTAssertEqual(vm.wirdDailyPages(p), 5)
    }

    func testDailyPages_pagesPerDay_coercesZeroToOne() {
        let p = makePrefs(type: .pagesPerDay, value: 0, startPage: 1)
        XCTAssertEqual(vm.wirdDailyPages(p), 1, "Daily pages must never be <1")
    }

    /// FINISH_IN_DAYS — (totalPages - startPage + 1) / days, floor, min 1.
    ///   Start page 1, 30 days → 604 / 30 = 20.13 → floor = 20
    func testDailyPages_finishInDays_fromPage1In30Days() {
        let p = makePrefs(type: .finishInDays, value: 30, startPage: 1)
        XCTAssertEqual(vm.wirdDailyPages(p), 20)
    }

    ///   Start page 303, 30 days → (604-303+1)/30 = 302/30 = 10.07 → floor = 10
    func testDailyPages_finishInDays_mid_Quran() {
        let p = makePrefs(type: .finishInDays, value: 30, startPage: 303)
        XCTAssertEqual(vm.wirdDailyPages(p), 10)
    }

    ///   Zero days → coerced to 1 → all remaining pages "today".
    func testDailyPages_finishInDays_coercesZeroDaysToOne() {
        let p = makePrefs(type: .finishInDays, value: 0, startPage: 1)
        XCTAssertEqual(vm.wirdDailyPages(p), 604)
    }

    /// JUZ_PER_DAY — juz count × (604/30). 1 juz/day → 20 pages.
    func testDailyPages_juzPerDay_oneJuz() {
        let p = makePrefs(type: .juzPerDay, value: 1, startPage: 1)
        // 1 * (604/30) = 20.133 → floor = 20
        XCTAssertEqual(vm.wirdDailyPages(p), 20)
    }

    ///   2 juz/day → 40 pages (well, 40.266 → 40).
    func testDailyPages_juzPerDay_twoJuz() {
        let p = makePrefs(type: .juzPerDay, value: 2, startPage: 1)
        XCTAssertEqual(vm.wirdDailyPages(p), 40)
    }

    // =========================================================================
    // MARK: wirdProgressColor — tier boundaries
    //
    // The 30-40-30-Beyond law is the whole point of the Locked Manifest's
    // momentum engine. These tests encode EXACTLY where the boundaries sit.
    // Any drift here means the user sees the wrong color at the wrong time.
    // =========================================================================

    func testProgressColor_redBelow30() {
        XCTAssertEqual(vm.wirdProgressColor(ratio: 0.0),  WarattilConstants.Colors.progressLow)
        XCTAssertEqual(vm.wirdProgressColor(ratio: 0.29), WarattilConstants.Colors.progressLow)
    }

    func testProgressColor_amberAt30Boundary() {
        // Exactly 0.30 is Amber (the >=0.30 arm).
        XCTAssertEqual(vm.wirdProgressColor(ratio: 0.30), WarattilConstants.Colors.progressMid)
        XCTAssertEqual(vm.wirdProgressColor(ratio: 0.69), WarattilConstants.Colors.progressMid)
    }

    func testProgressColor_greenAt70Boundary() {
        // Exactly 0.70 is Green (the >=0.70 arm).
        XCTAssertEqual(vm.wirdProgressColor(ratio: 0.70), WarattilConstants.Colors.progressHigh)
        XCTAssertEqual(vm.wirdProgressColor(ratio: 0.99), WarattilConstants.Colors.progressHigh)
        // Exactly 1.00 is STILL Green — only >1.0 flips to Blue.
        XCTAssertEqual(vm.wirdProgressColor(ratio: 1.00), WarattilConstants.Colors.progressHigh)
    }

    func testProgressColor_skyBlueAbove100() {
        // 1.0000001 is Blue (the >1.0 arm).
        XCTAssertEqual(vm.wirdProgressColor(ratio: 1.01), WarattilConstants.Colors.progressBeyond)
        XCTAssertEqual(vm.wirdProgressColor(ratio: 2.5),  WarattilConstants.Colors.progressBeyond)
    }

    // =========================================================================
    // MARK: wirdProgressRatio — fallback behaviour (no wird configured)
    // =========================================================================

    /// When no wird is set, the ratio falls back to currentPage / 604 so the
    /// momentum bar tracks whole-Quran completion.
    func testProgressRatio_noWird_fallsBackToQuranCompletion() {
        // No wird → ratio = page/604.
        let ratioAtStart    = vm.wirdProgressRatio(currentPage: 1,   p: nil)
        let ratioAtHalf     = vm.wirdProgressRatio(currentPage: 302, p: nil)
        let ratioAtEnd      = vm.wirdProgressRatio(currentPage: 604, p: nil)

        XCTAssertEqual(ratioAtStart, 1.0 / 604.0, accuracy: 0.0001)
        XCTAssertEqual(ratioAtHalf,  302.0 / 604.0, accuracy: 0.0001)
        XCTAssertEqual(ratioAtEnd,   1.0,        accuracy: 0.0001)
    }

    // =========================================================================
    // MARK: wirdProgressRatio — wird active
    //
    // Construct a wird starting "today" (daysElapsed = 0) with PAGES_PER_DAY = 5.
    //   todayTarget = startPage + (0+1)*5 = startPage + 5
    //   todayStart  = todayTarget - 5 + 1 = startPage + 1
    //   pagesRead   = currentPage - (startPage+1) + 1 = currentPage - startPage
    //   ratio       = pagesRead / 5
    // =========================================================================

    func testProgressRatio_wirdActive_dayZero_pagesPerDay() {
        let prefs = makePrefsActiveToday(type: .pagesPerDay, value: 5, startPage: 1)

        // currentPage 1 → pagesRead = 0 → ratio = 0.0 (before day starts effectively)
        XCTAssertEqual(vm.wirdProgressRatio(currentPage: 1, p: prefs), 0.0, accuracy: 0.0001)

        // currentPage 3 → pagesRead = 2 → ratio = 0.4
        XCTAssertEqual(vm.wirdProgressRatio(currentPage: 3, p: prefs), 0.4, accuracy: 0.0001)

        // currentPage 6 → pagesRead = 5 → ratio = 1.0 (exactly at goal)
        XCTAssertEqual(vm.wirdProgressRatio(currentPage: 6, p: prefs), 1.0, accuracy: 0.0001)

        // currentPage 8 → pagesRead = 7 → ratio = 1.4 (surpassed by 2 pages)
        XCTAssertEqual(vm.wirdProgressRatio(currentPage: 8, p: prefs), 1.4, accuracy: 0.0001)
    }

    // =========================================================================
    // MARK: wirdProgressMessage — Arabic wording parity with Android
    //
    // These tests lock the EXACT Arabic strings from the Kotlin source so
    // the iOS footer reads identically. Copy-paste mistakes here would be
    // invisible until shipped.
    // =========================================================================

    // --- Fallback (no wird) ---

    func testMessage_noWird_tiers() {
        // Low: page 1 → ratio ≈ 0.0017 → Red → "بداية مباركة"
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: 1.0 / 604.0, p: nil, currentPage: 1),
            "بداية مباركة"
        )
        // Amber: ratio 0.5 → "عزيمة وإصرار"
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: 0.5, p: nil, currentPage: 302),
            "عزيمة وإصرار"
        )
        // Green: ratio 0.9 → "شارفت على الختم"
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: 0.9, p: nil, currentPage: 540),
            "شارفت على الختم"
        )
        // Sky Blue: ratio 1.5 → "ختمة جديدة مباركة"
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: 1.5, p: nil, currentPage: 604),
            "ختمة جديدة مباركة"
        )
    }

    // --- Wird active ---

    func testMessage_wirdActive_belowDailyGoal_red() {
        let prefs = makePrefsActiveToday(type: .pagesPerDay, value: 10, startPage: 1)
        // day 0: todayTarget = 11; currentPage 1 → below 30%
        let ratio = vm.wirdProgressRatio(currentPage: 1, p: prefs)
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: ratio, p: prefs, currentPage: 1),
            "ابدأ وردك اليوم"
        )
    }

    func testMessage_wirdActive_belowDailyGoal_amber() {
        let prefs = makePrefsActiveToday(type: .pagesPerDay, value: 10, startPage: 1)
        // day 0: todayStart=2, pagesRead at currentPage 6 = 5, ratio=0.5 → Amber
        let ratio = vm.wirdProgressRatio(currentPage: 6, p: prefs)
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: ratio, p: prefs, currentPage: 6),
            "عزيمة وإصرار"
        )
    }

    func testMessage_wirdActive_belowDailyGoal_green() {
        let prefs = makePrefsActiveToday(type: .pagesPerDay, value: 10, startPage: 1)
        // day 0: pagesRead at currentPage 9 = 8, ratio=0.8 → Green (approaching goal)
        let ratio = vm.wirdProgressRatio(currentPage: 9, p: prefs)
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: ratio, p: prefs, currentPage: 9),
            "شارفت على إتمام وردك"
        )
    }

    func testMessage_wirdActive_exactlyAtTarget() {
        let prefs = makePrefsActiveToday(type: .pagesPerDay, value: 5, startPage: 1)
        // day 0: todayTarget = 6, currentPage 6 → diff == 0 → exact completion
        XCTAssertEqual(
            vm.wirdProgressMessage(ratio: 1.0, p: prefs, currentPage: 6),
            "أتممت ورد اليوم"
        )
    }

    func testMessage_wirdActive_surpassedTarget_showsDuaa() {
        let prefs = makePrefsActiveToday(type: .pagesPerDay, value: 5, startPage: 1)
        // day 0: todayTarget = 6, currentPage 8 → diff = -2 → Sky Blue Duaa.
        //
        // The message is deterministically picked by (currentPage % list.count).
        // We don't hardcode a specific Duaa — we just check it's ONE of the five.
        let msg = vm.wirdProgressMessage(ratio: 1.4, p: prefs, currentPage: 8)

        let duaaList: Set<String> = [
            "تقبّل الله طاعتك وزادك حرصاً",
            "هنيئاً لك زيادة الخير",
            "بارك الله في همّتك ووقتك",
            "اللهم اجعلنا من أهل القرآن",
            "زادك الله علماً وعملاً وتوفيقاً"
        ]
        XCTAssertTrue(duaaList.contains(msg), "Surpassed-goal message should be a Duaa; got: \(msg)")
    }

    /// Deterministic rotation: same currentPage should always pick the same Duaa
    /// (no randomness → stable SwiftUI recomposition).
    func testMessage_wirdActive_surpassedTarget_duaaIsStablePerPage() {
        let prefs = makePrefsActiveToday(type: .pagesPerDay, value: 5, startPage: 1)
        let msg1 = vm.wirdProgressMessage(ratio: 1.4, p: prefs, currentPage: 8)
        let msg2 = vm.wirdProgressMessage(ratio: 1.4, p: prefs, currentPage: 8)
        XCTAssertEqual(msg1, msg2, "Same page must always pick the same Duaa")
    }

    // =========================================================================
    // MARK: Test helpers
    // =========================================================================

    /// Prefs with wirdStartDate == nil — the "no wird configured" state.
    private func makePrefs(type: ReadingTargetType, value: Int, startPage: Int)
        -> UserPreferences
    {
        UserPreferences(
            id:              1,
            lastReadPage:    1,
            wirdTargetType:  type,
            wirdTargetValue: value,
            wirdStartDate:   nil,
            wirdStartPage:   startPage,
            wirdLastCompletedPage: 0
        )
    }

    /// Prefs with wirdStartDate == "today" (same epoch-ms as Date() at call
    /// time, so daysElapsed = 0 when the VM computes it).
    private func makePrefsActiveToday(type: ReadingTargetType, value: Int, startPage: Int)
        -> UserPreferences
    {
        UserPreferences(
            id:              1,
            lastReadPage:    startPage,
            wirdTargetType:  type,
            wirdTargetValue: value,
            wirdStartDate:   Int64(Date().timeIntervalSince1970 * 1000),
            wirdStartPage:   startPage,
            wirdLastCompletedPage: 0
        )
    }
}
