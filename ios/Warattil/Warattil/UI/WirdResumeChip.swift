//
//  WirdResumeChip.swift
//  Warattil
//
//  Ports app/src/main/java/com/warattil/app/ui/WirdResumeChip.kt to SwiftUI.
//
//  «↩ تابع وردك · ص N»
//
//  Calm, optional affordance for returning to the wird ribbon after a
//  jump.  Renders as a single-line gold-tinted pill embedded INLINE
//  inside MushaFFooter's first row, alongside the momentum message.
//
//  Locked behavior (parity with Android):
//    • Zero required action during sequential reading.  The chip is
//      hidden when currentPage is on or near the wird ribbon (±2 pages
//      tolerance — see MushaFViewModel.wirdResumePage).
//    • One optional tap to return after a real jump (Friday Al-Kahf,
//      Fihris navigation, search-to-page).
//    • Single line, plain Arabic, no jargon — readable at a glance by
//      elder users.
//    • Page digits in `.system` font so the KFGQPC GSUB digit→ayah-
//      badge ligature doesn't mangle 3-digit page numbers like ١٠٣.
//
//  Returns just the pill — no outer Row / fillMaxWidth wrapper.  The
//  caller (FooterWirdActive in MushaFFooter) places this alongside
//  the message in its own Row.
//

import SwiftUI

struct WirdResumeChip: View {

    let resumePage: Int
    let theme:      ThemeColors
    let onTap:      () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text("↩")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
            Text("تابع وردك")
                .font(.warattilChrome(size: 12, weight: .semibold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold.opacity(0.55))
            Text("ص \(resumePage.arabicDigits)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WarattilConstants.Hifz.hifzGold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(WarattilConstants.Hifz.hifzGold.opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke(WarattilConstants.Hifz.hifzGold.opacity(0.45), lineWidth: 0.75)
        )
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
