//
//  ShareUtil.swift
//  Warattil
//
//  Mirrors app/src/main/java/com/warattil/app/core/ShareUtil.kt — the Android
//  file handles two separate share payloads, and this Swift port keeps both
//  intact but surfaces them as pure-string builders. The SwiftUI view layer
//  is responsible for actually presenting them via `ShareLink` or
//  `UIActivityViewController` — see AyahActionBar.swift (still to come).
//
//  Two payload formats exist and must stay DISTINCT:
//
//  1) Ayah-share payload (locked — BLUEPRINT §11.3). Used from the long-press
//     action bar. No hadith framing, no tagline, one em-dash signature line.
//
//  2) App-share payload (BLUEPRINT §11.4). Used from the overflow-menu
//     "شارك ورتّل" item. DOES carry the hadith framing — this is a one-time
//     invitation, not recurring content.
//

import Foundation
import UIKit

public enum ShareUtil {

    /// Canonical App Store listing URL — single source of truth for every
    /// share payload. When the brand domain is eventually registered, update
    /// this constant only and both share paths pick up the change
    /// automatically. BLUEPRINT §2.8 — do NOT introduce a URL shortener.
    ///
    /// NOTE: the app must be created in App Store Connect before this URL
    /// resolves. Until then TestFlight links are fine for internal share.
    /// See ios/docs/KICKOFF.md for the enrollment checklist.
    public static let appStoreURL =
        "https://apps.apple.com/app/id6766103481"

    /// Brand redirect URL — UA-sniffing on Nasser's host sends Android users to
    /// Play Store and iOS users to the App Store. This is what the bundled QR
    /// code encodes, so it MUST stay byte-identical to the value the QR was
    /// generated from.  Used wherever we want a single cross-platform link
    /// (QR share, rich-preview URLs for Facebook/Twitter).
    public static let brandRedirectURL = "https://warattil.org/get"

    // -------------------------------------------------------------------------
    // Ayah share payload — the locked four-line format from BLUEPRINT §11.3.
    //
    // ﴿ {text with annotations stripped} ﴾
    // سورة {surahName} · الآية {n.arabicDigits}
    //
    // — تطبيق ورتّل
    // {App Store URL}
    // -------------------------------------------------------------------------

    /// Format an ayah for sharing. This is the single canonical formatter —
    /// do NOT call ad-hoc string interpolation elsewhere. The Android
    /// counterpart lives in `AyahActionBar.formatAyahForShare`; keep them in
    /// lockstep. See BLUEPRINT §11.3.
    public static func formatAyahForShare(
        text: String,
        surahName: String,
        ayahNumber: Int
    ) -> String {
        let cleanText = stripAnnotations(text)
        // Four lines exactly. The blank line separating the citation from the
        // signature is load-bearing — removing it concatenates them in plain
        // messaging apps and breaks the aesthetic.
        return """
        ﴿ \(cleanText) ﴾
        سورة \(surahName) · الآية \(ayahNumber.arabicDigits)

        — تطبيق ورتّل
        \(appStoreURL)
        """
    }

    /// Format a contiguous ayah RANGE for sharing (single surah only — cross-
    /// surah ranges would change the citation line format and are not a use
    /// case the reader asked for).  The text arguments are already joined
    /// with a single space between ayahs and annotations stripped per-ayah
    /// before joining; this helper only frames them.
    ///
    /// Each individual ayah still has its number rendered inline via a
    /// rosette-style ۝ marker in the *body* so the receiving reader can see
    /// the boundaries without us needing to re-render a MushaF page.  The
    /// citation line switches from "الآية n" to "الآيات m–n" when the range
    /// spans more than one ayah.
    public static func formatAyahRangeForShare(
        text: String,
        surahName: String,
        fromAyah: Int,
        toAyah: Int
    ) -> String {
        // Clean as a whole — the annotation range U+06D6–U+06ED is a contiguous
        // block of combining marks, so whether we strip before or after joining
        // is equivalent (ASCII-safe strip on non-ASCII text).
        let cleanText = stripAnnotations(text)
        let citation: String
        if fromAyah == toAyah {
            citation = "سورة \(surahName) · الآية \(fromAyah.arabicDigits)"
        } else {
            // "الآيات ١–٣" — U+2013 EN DASH between numbers, matching the
            // Android formatter's output exactly.  NOT a hyphen-minus; many
            // Arabic-facing receivers treat the EN DASH as the correct range
            // separator and hyphen-minus as a literal character.
            citation = "سورة \(surahName) · الآيات \(fromAyah.arabicDigits)–\(toAyah.arabicDigits)"
        }
        return """
        ﴿ \(cleanText) ﴾
        \(citation)

        — تطبيق ورتّل
        \(appStoreURL)
        """
    }

    /// Strip Quranic annotation marks (U+06D6–U+06ED) from an ayah before
    /// sharing. These marks render inconsistently in plain-text messaging
    /// apps; removing them keeps the shared text clean. Diacritics (tashkeel,
    /// U+064B–U+0652) and the Uthmani-specific marks OUTSIDE this range are
    /// preserved. BLUEPRINT §11.3.
    public static func stripAnnotations(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            !(scalar.value >= 0x06D6 && scalar.value <= 0x06ED)
        })
    }

    // -------------------------------------------------------------------------
    // App share payload — BLUEPRINT §11.4. Hadith-framed invitation.
    // -------------------------------------------------------------------------

    public static let appShareSubject = "ورتّل — مصحف رقمي"
    public static let appShareChooserTitle = "شارك ورتّل"

    /// Body of the "شارك ورتّل" share. Arabic, plain text, no Markdown.
    public static var appShareText: String {
        """
        ورتّل — مصحف رقمي بخط عثماني كامل، بلا إعلانات ولا إلهاء.
        اقرأ، احفظ، وتابع وردك اليومي.

        قال النبي ﷺ: «من دلَّ على خير فله مثل أجر فاعله»

        \(appStoreURL)
        """
    }

    /// Present the system share sheet for the "شارك ورتّل" invitation, with
    /// the rendered AppInviteShareCard image attached.  Multi-item payload
    /// mirrors shareHifzGarden / shareDailyReading — each destination picks
    /// the subset it can render:
    ///   • Instagram Stories  → image only
    ///   • Facebook / Twitter → image + URL (rich preview with the card)
    ///   • WhatsApp / Telegram → image + text body
    ///   • SMS / Mail         → everything
    ///
    /// If `image` is nil (snapshot renderer failed — shouldn't happen on a
    /// 720 pt card) this falls back to the text-only invite so the share
    /// path never silently dead-ends on the user.
    public static func shareAppInvite(image: UIImage?) {
        var items: [Any] = []
        if let image { items.append(image) }
        items.append(appShareText)
        if let url = URL(string: brandRedirectURL) { items.append(url) }
        presentActivity(items: items, subject: appShareSubject)
    }

    // -------------------------------------------------------------------------
    // MARK: Hifz garden image share — BLUEPRINT §11.5
    //
    //   Mirrors Android's ShareUtil.shareHifzGarden(context, bitmap).  The
    //   caller renders the HifzLogSheet heatmap to a UIImage (SwiftUI
    //   ImageRenderer or UIGraphicsImageRenderer) and hands it here; we
    //   present a UIActivityViewController with the image + short invitation
    //   body.  Receiving apps that honour only one attachment type (WhatsApp,
    //   Telegram) will prefer the image and drop the text — that's fine,
    //   the image already carries the "ورتّل" wordmark + warattil.org/get
    //   caption drawn at the rendering site.
    //
    //   Why UIActivityViewController and not SwiftUI's ShareLink:
    //     • ShareLink with an Image item copies the pixel buffer into the
    //       share sheet via a transferable, which on iOS 16.x occasionally
    //       returns a nil UIImage on the receiving side (FB11958543).
    //     • UIActivityViewController is the stable path on every iOS 15+
    //       device and matches Android's ACTION_SEND semantics exactly.
    // -------------------------------------------------------------------------

    /// Subject line set on Mail.app share; other targets ignore.
    public static let gardenShareSubject = "خريطة حفظي في ورتّل"

    /// Short invitation body.  Intentionally brief — the image IS the message.
    public static var gardenShareText: String {
        """
        هذه خريطة حفظي في ورتّل.
        \(appStoreURL)
        """
    }

    /// Present the system share sheet with a rendered Hifz-garden image.
    ///
    /// Finds the frontmost window scene's root view controller and
    /// presents a `UIActivityViewController` with `[image, gardenShareText]`
    /// as the activity items.  On iPad the popover anchors to the centre
    /// of the presenter's view — an acceptable fallback when the caller
    /// doesn't pass a source rect, and prevents the "unsupported
    /// popover presentation" crash that UIKit raises when an iPad tries
    /// to present a UIActivityViewController as a modal sheet.
    ///
    /// No-op if there is no key window scene (e.g. app backgrounded
    /// mid-tap) — matching the Android implementation's quiet fail rather
    /// than crashing the reader.
    public static func shareHifzGarden(image: UIImage) {
        // Multi-item payload: image + short body + brand URL.  Each
        // destination app picks what it accepts:
        //   • Instagram / Stories  → image
        //   • Facebook / Twitter   → image + URL (rich preview)
        //   • WhatsApp / Telegram  → image + text
        //   • Mail / Messages      → everything
        // Receivers that only take one attachment (WhatsApp image-only path)
        // drop the rest cleanly — no aesthetic regression.
        var items: [Any] = [image, gardenShareText]
        if let url = URL(string: brandRedirectURL) { items.append(url) }
        presentActivity(items: items, subject: gardenShareSubject)
    }

    // -------------------------------------------------------------------------
    // MARK: QR code share — BLUEPRINT §11.6
    //
    //   The bundled WarattilQR asset (Assets.xcassets → "WarattilQR") encodes
    //   `brandRedirectURL` and is displayed in AboutSheet.  Some readers want
    //   to send the code itself as an image to a friend's WhatsApp so the
    //   friend can scan it directly — avoids the "what's the URL? let me spell
    //   it" back-and-forth.
    //
    //   The activity items are: [image, caption, URL].  Facebook / Twitter
    //   latch onto the URL and synthesise a rich preview; Instagram Stories
    //   uses the image; WhatsApp / Telegram attach the image and drop the URL
    //   as a line of the message.
    // -------------------------------------------------------------------------

    public static let qrShareSubject = "رمز ورتّل"

    /// Caption for the QR share.  Short — the QR IS the payload.
    public static var qrShareText: String {
        """
        امسح الرمز لتحميل تطبيق ورتّل.
        \(brandRedirectURL)
        """
    }

    /// Present the system share sheet with the bundled QR PNG.
    /// No-op if the asset is missing (shouldn't happen, but quiet-fail beats
    /// crashing the reader).  The asset name MUST stay "WarattilQR" — it's
    /// the name ShareUtil agrees on with AboutSheet.
    public static func shareQRCode() {
        guard let image = UIImage(named: "WarattilQR") else { return }
        var items: [Any] = [image, qrShareText]
        if let url = URL(string: brandRedirectURL) { items.append(url) }
        presentActivity(items: items, subject: qrShareSubject)
    }

    // -------------------------------------------------------------------------
    // MARK: Daily reading status share — BLUEPRINT §11.7
    //
    //   Caller renders `DailyReadingShareCard` to a UIImage via its
    //   `renderSnapshot` helper.  Activity items are [image, caption, URL]
    //   so Facebook / Twitter / Instagram / WhatsApp each pick up the subset
    //   they render best.  Single canonical caption lives here — do NOT
    //   duplicate the Arabic body text at the call site.
    // -------------------------------------------------------------------------

    public static let dailyShareSubject = "ورد اليوم · ورتّل"

    /// Short caption accompanying the rendered card.
    public static var dailyShareText: String {
        """
        ورد اليوم مع ورتّل.
        \(brandRedirectURL)
        """
    }

    /// Present the system share sheet with the rendered daily-reading card.
    /// No-op if the image is nil (shouldn't happen — `renderSnapshot` returns
    /// nil only when ImageRenderer fails, which we treat as a quiet no-op
    /// rather than crashing the reader mid-share).
    public static func shareDailyReading(image: UIImage) {
        var items: [Any] = [image, dailyShareText]
        if let url = URL(string: brandRedirectURL) { items.append(url) }
        presentActivity(items: items, subject: dailyShareSubject)
    }

    // -------------------------------------------------------------------------
    // MARK: Hifz milestone (tier-crossing) image share
    //
    //   Mirrors V3 Android's ShareUtil.shareHifzMilestone(context, bitmap).
    //   Caller renders HifzCelebrationDialog's content via ImageRenderer
    //   on the "شارك فرحتك" tap and hands the UIImage here.  Earlier the
    //   dialog's share button fell through to shareAppInvite — which sent
    //   a generic invite, not the actual milestone card.  With image
    //   capture the receiver sees the rendered celebration card so the
    //   share carries the same gravity as the moment itself.
    //
    //   Caption is intentionally brief — the rendered card already
    //   carries the tier label, juz count, du'a line, and "ورتّل ·
    //   warattil.org/get" attribution strip.  The caption just
    //   reaffirms the milestone in plain text for receivers that drop
    //   the image (rare).
    // -------------------------------------------------------------------------

    public static let milestoneShareSubject = "مرحلة جديدة في حفظي · ورتّل"

    public static var milestoneShareText: String {
        """
        بفضل الله، بلغتُ مرحلةً جديدة في رحلة حفظ القرآن.
        \(brandRedirectURL)
        """
    }

    /// Present the system share sheet with the rendered Hifz-milestone card.
    /// No-op if `image` is nil — quiet-fail matches every other image-share
    /// path here and beats crashing the reader at a celebratory moment.
    public static func shareHifzMilestone(image: UIImage?) {
        guard let image else { return }
        var items: [Any] = [image, milestoneShareText]
        if let url = URL(string: brandRedirectURL) { items.append(url) }
        presentActivity(items: items, subject: milestoneShareSubject)
    }

    // -------------------------------------------------------------------------
    // MARK: Shared presenter — activity sheet bring-up
    //
    //   Single place that walks the window-scene → root VC → topmost presented
    //   VC chain and presents a UIActivityViewController.  Adding a new share
    //   surface (daily-reading card, app-invite card) is a one-liner call into
    //   this helper, not a copy-paste of the scene-walking boilerplate.
    //
    //   iPad popover anchor pins to the presenter's view centre — harmless on
    //   iPhone, prevents the "unsupported popover presentation" crash on iPad.
    // -------------------------------------------------------------------------

    private static func presentActivity(items: [Any], subject: String? = nil) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController
        else { return }

        // Walk to the topmost presented controller so we don't try to
        // present a chooser on top of an already-visible sheet.
        var presenter: UIViewController = rootVC
        while let next = presenter.presentedViewController {
            presenter = next
        }

        let activity = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        if let subject { activity.setValue(subject, forKey: "subject") }  // Mail.app reads this

        // iPad — anchor the popover to the presenter's view centre.
        if let pop = activity.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0, height: 0
            )
            pop.permittedArrowDirections = []
        }

        presenter.present(activity, animated: true)
    }
}
