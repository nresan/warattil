//
//  QuranMetadata.swift
//  Warattil
//
//  Data models backing MetadataParser + the Eastern-Arabic-digit helper.
//  Mirrors app/src/main/java/com/warattil/app/data/QuranMetadata.kt.
//

import Foundation

// =============================================================================
// Metadata record types — direct 1:1 ports of the Kotlin data classes.
// =============================================================================

public struct SuraMetadata: Equatable, Hashable {
    public let index: Int    // 1-based surah number
    public let name: String  // Arabic name (e.g. "الفاتحة")
    public let ayas: Int     // total ayah count in the surah
    public let start: Int    // absolute ayah offset from the start of the Mushaf

    public init(index: Int, name: String, ayas: Int, start: Int) {
        self.index = index
        self.name = name
        self.ayas = ayas
        self.start = start
    }
}

public struct PageMetadata: Equatable, Hashable {
    public let index: Int  // 1..604
    public let sura: Int
    public let aya: Int

    public init(index: Int, sura: Int, aya: Int) {
        self.index = index
        self.sura = sura
        self.aya = aya
    }
}

public struct JuzMetadata: Equatable, Hashable {
    public let index: Int  // 1..30
    public let sura: Int
    public let aya: Int

    public init(index: Int, sura: Int, aya: Int) {
        self.index = index
        self.sura = sura
        self.aya = aya
    }
}

// =============================================================================
// Eastern-Arabic-digit helper
//
// All numbers rendered in the reading chrome (ayah markers, page numbers, juz
// numbers, percentages) MUST be Eastern Arabic digits (٠١٢٣٤٥٦٧٨٩).
// Latin digits (0–9) must not appear in any reading-surface string.
// See BLUEPRINT §2.3.
// =============================================================================

public extension Int {
    /// Map Latin 0–9 → Eastern Arabic ٠–٩. Example: 604 → "٦٠٤".
    var arabicDigits: String {
        String(self).map { ch -> Character in
            guard let ascii = ch.asciiValue,
                  ascii >= 0x30, ascii <= 0x39 else { return ch }
            return Character(UnicodeScalar(0x0660 + Int(ascii - 0x30))!)
        }.map(String.init).joined()
    }
}

public extension Optional where Wrapped == Int {
    /// Nil-safe variant: returns "" if the int is missing.
    var arabicDigits: String {
        self?.arabicDigits ?? ""
    }
}
