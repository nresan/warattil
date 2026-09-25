//
//  JustifiedArabicText.swift
//  Warattil
//
//  *** DEAD CODE — kept only because the file cannot be deleted from the
//  mount. Safe to remove from the Xcode project next time the workspace is
//  opened locally. ***
//
//  History: wrapped a UILabel so we could render Arabic ayah text with
//  NSTextAlignment.justified. Abandoned 2026-04-20 when we switched to the
//  KFGQPC per-page glyph fonts (tools/qcf/README.md) — those fonts solve
//  the "identical block" layout problem at the font level, so we no
//  longer need a justifier.
//
//  Remove by:
//    1) Deleting this file from disk.
//    2) Removing the corresponding `PBXFileReference` entries from
//       Warattil.xcodeproj (Xcode 16's synchronized-folder group handles
//       this automatically if you delete the file in Finder while Xcode
//       is open).
//

import Foundation
