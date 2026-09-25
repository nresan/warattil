# WARATTIL iOS — First Launch Walkthrough

This is the hand-held guide for the **first time you open `Warattil.xcodeproj`** on your Mac and try to run the app. It assumes you've never used Xcode before, or only briefly.

Companion docs (historical reference only — project has moved on):

- `BLUEPRINT.md` — canonical spec (still current).
- `KICKOFF.md` — status snapshot from 2026-04-19. Much of "what's not done" is now done. Treat as history.

---

## What you're about to open

The project under `ios/Warattil/` has a single Xcode project file: `Warattil.xcodeproj`. Everything the app needs — Swift source, bundled Quran database, fonts, tests — is already inside it. You don't need Gradle-equivalent build wiring or a package manager step.

High-level targets in the project:

| Target          | What it is                                                                 |
|-----------------|----------------------------------------------------------------------------|
| `Warattil`      | The iPhone app itself — what you'll run on the simulator or device.        |
| `WarattilTests` | XCTest suite — runs the paging / repository / VM tests. Runs with ⌘U.      |
| `WarattilUITests` | Placeholder — Xcode generated this automatically, we aren't using it yet. |

Current size on disk: ~64 MB of Resources (mostly QCF fonts + the Quran database). That lands in the built app bundle too — expect a ~74 MB `.ipa` later.

---

## Before you start

You need:

1. **Xcode installed** (ideally 16 or later — the project's `.pbxproj` uses Xcode 16-style synchronized file groups).
2. **At least one iOS 17+ simulator runtime available.** The app's deployment target is iOS 17.0. Most Xcode 16 installs ship with the current-year simulator preinstalled; if not, Xcode will prompt you.
3. **Your Mac connected to the internet for the first build** — CocoaPods / SPM packages aren't used here, but Xcode occasionally needs to fetch provisioning profiles the first time a target is signed.

You do **not** need:

- An Apple Developer Program membership to run on the simulator. You only need that for TestFlight / App Store.
- An Apple Developer Program membership for on-device debugging either, if you're OK with Personal Team signing (Xcode re-signs every 7 days; fine for now).

---

## Step 1 — Open the project

In Finder, double-click `ios/Warattil/Warattil.xcodeproj`.

Do **not** open the folder as a workspace, don't open `Package.swift`, don't open any individual `.swift` file — Xcode gets confused and will build the wrong thing. Always open the project file directly.

First time you open it, Xcode takes 30–60 seconds to index everything. You'll see a progress indicator in the top-center status bar ("Indexing Warattil…"). Wait for it to finish before building — building during indexing produces confusing error messages.

---

## Step 2 — Pick a simulator

Top of the Xcode window, next to the project name, there's a device picker (looks like `> iPhone 15 Pro Max` or similar). Click it and choose an iPhone simulator. Recommended:

- **iPhone 15 Pro** or **iPhone 16 Pro** — 6.1", standard display size.
- Any iOS 17+ simulator. Don't pick an iPad; iPad layout isn't tuned yet.

If the list is empty or greyed out:

1. Xcode → Settings (⌘,) → **Platforms** tab.
2. Click **+** and add "iOS 17.0" (or the current latest).
3. It's a ~8 GB download. Let it finish, then re-open the project.

---

## Step 3 — Signing (only matters for on-device runs)

This step is only relevant if you're running on your **actual iPhone**, not the simulator. Skip to Step 4 if you're staying on the simulator for now.

1. Click the blue **Warattil** project icon at the top of the Project Navigator (left sidebar).
2. In the middle pane, under TARGETS, click **Warattil** (the app target — not WarattilTests).
3. Open the **Signing & Capabilities** tab.
4. Tick **Automatically manage signing**.
5. Under **Team**, pick your Apple ID. If you've never signed anything before, click "Add an Account…" and log in with the Apple ID you want tied to WARATTIL.
6. First time only, Xcode says "Personal Team" next to your account. That's fine. Personal Team apps work on your devices for 7 days before you have to re-sign them. Good enough to evaluate the rendering.

If Xcode complains the bundle ID `com.warattil.warattilmushaf` is taken: change it temporarily to `com.warattil.warattilmushaf.nresan` in the same Signing screen. The real bundle ID is reserved for the actual App Store submission path. **Do not commit this change** — only change it in your local Xcode session.

---

## Step 4 — First build

Press **⌘R** (Product → Run).

What should happen:

1. Xcode compiles everything. First compile is 30–90 seconds; subsequent incremental compiles are ~5 seconds.
2. The iPhone simulator window opens.
3. You see a cream background with a green spinner for about one frame.
4. The Mushaf appears: Al-Fatiha, centered, rendered in the KFGQPC per-page font.
5. The header shows the surah name, juz number (Arabic digit), and page number (Arabic digit).
6. The footer shows a red progress bar (you're on page 1 of 604, <30%) with an Arabic status message.

If the simulator window looks black or stays on the spinner, see Troubleshooting below.

---

## Step 5 — Smoke-test checklist

Run through these in order to verify each layer is working:

**Rendering (QCF fonts + page layout)**

- [ ] Al-Fatiha renders with proper Uthmani shaping — not a plain Arabic system font.
- [ ] The surah-header banner at the top has a gold border and the surah title in serif.
- [ ] The basmala line (where applicable) is centered and visually heavier than the body.
- [ ] Text lines fill the full width edge-to-edge — no trailing or leading gaps.
- [ ] Page numbers in header/footer are Eastern Arabic digits (١, ٢, ٣) — not 1, 2, 3.

**Paging**

- [ ] Swipe right-to-left to advance. The Mushaf direction is RTL, so a natural right-to-left finger drag goes to the NEXT page.
- [ ] Swipe through pages 1–10. None should be blank or broken.
- [ ] Jump to page 106 (swipe lots, or quit + come back after you've marked page 106 as last-read) — page 106 should show the tail of An-Nisa and the head of Al-Maida, with a surah-header banner in the middle.
- [ ] Swipe to the last page. Page 604 should end with An-Nas (surah 114, ayah 6).

**Ayah selection (long-press → Copy / Share)**

- [ ] Long-press any body text line. A context menu appears after ~0.5 seconds.
- [ ] Menu has one section per ayah on that line (usually 1, up to 4).
- [ ] Each section shows the ayah label in Arabic, e.g. "سورة الفاتحة · الآية ٢".
- [ ] Tap "نسخ" (Copy) — feel a light haptic; the clean Uthmani text (not PUA glyphs) lands on the pasteboard.
- [ ] Paste into any other app to verify — you should see diacriticised Arabic, not garbled boxes.
- [ ] Tap "مشاركة" (Share) — system share sheet appears with the four-line payload (ayah text + citation + signature + App Store URL).

**Momentum bar**

- [ ] Page 1 → bar is at far-left, red, message "بداية مباركة".
- [ ] Swipe to around page 180 → bar grows, message becomes "عزيمة وإصرار" (amber).
- [ ] Swipe to around page 430 → bar is green, message "شارفت على الختم".
- [ ] Swipe to page 604 → bar fills edge-to-edge, sky-blue, celebration message.

**Persistence**

- [ ] Advance to page 42.
- [ ] Stop the app (⌘. in Xcode, or close the simulator app).
- [ ] ⌘R again — the app should open straight to page 42, not page 1.

If all of these pass, the QCF architecture is truly working end-to-end. If any of them fail, the Troubleshooting section below has the first things to check.

---

## Step 6 — Run the unit tests

Press **⌘U** (Product → Test).

Expected result: all tests pass (~50+ tests across `MetadataParserTests`, `QuranRepositoryTests`, `MushaFViewModelTests`).

The tests touch the bundle, load the 604-page XML fixture, open `quran_v3.db`, and exercise the repository + VM logic. They take 10–20 seconds on a simulator.

If a test fails, the failure line points at the specific assertion. Send me the failing test name and the failure message; most failures will be bundle-path or provisioning issues rather than real code regressions.

Note: the test targets currently have `IPHONEOS_DEPLOYMENT_TARGET = 26.4`, which is too new — tests will only launch on an iOS 26.4+ simulator. Your iPhone is on 26.4.1 so that works on-device, but on the Mac you'll need the iOS 26.x simulator runtime installed. See "Cleanup items" below for how to lower it.

---

## Cleanup items (safe to defer, but worth knowing about)

These are small fixups that the Cowork session couldn't make from outside Xcode because of mount restrictions. Next time you have Xcode open, it'd take you five minutes total:

**1. Delete the dead `JustifiedArabicText.swift`**
In the Project Navigator, open `Warattil → UI → JustifiedArabicText.swift`. The file is a stub with just a comment saying "dead code — remove me". Right-click → Delete → **Move to Trash**. This removes it from the project and from disk.

**2. Delete `quran_v2.db` from Resources**
In the Project Navigator, open `Warattil → Resources → quran_v2.db`. Right-click → Delete → **Move to Trash**. The app reads `quran_v3.db`; `quran_v2.db` is ~1.7 MB of dead weight in the bundle.

**3. Lower the test targets' deployment target to 17.0**
Click the project → TARGETS → **WarattilTests** → **General** tab → **Minimum Deployments** → change from "iOS 26.4" to "iOS 17.0". Repeat for `WarattilUITests`. Commit the change.

**4. Double-check bundle ID if you get a signing error on first device run**
See Step 3 above — you may need to suffix the bundle ID with your name temporarily.

None of these block evaluating the app on the simulator. Do them in a quiet moment.

---

## Troubleshooting

**The app launches but shows boxes / garbled text instead of Arabic**

Fonts didn't register. `FontRegistrar.registerBundledFonts()` is called at app launch and logs registration failures to the Xcode console (bottom pane — View → Debug Area → Activate Console). Look for lines starting with "⚠️ FontRegistrar". The most common cause is a Resources path issue — open `Warattil → Resources → Fonts → qcf` in the Project Navigator and confirm the QCF_P*.woff2 files are all blue (included), not grey (excluded from target).

**App shows "تعذّر فتح المصحف" (couldn't open Mushaf)**

The bootstrap couldn't copy `quran_v3.db` from the bundle to the Documents directory. This usually means `quran_v3.db` isn't being packaged into the bundle. Select `quran_v3.db` in the Project Navigator → File Inspector (right sidebar) → under "Target Membership", tick `Warattil`. Rebuild.

**Blank pages after the first swipe**

The pager fires `ensureLoaded(page)` for every visible page. If a page stays blank, it usually means the repository threw an error in the background. Check the console for "failed to load page X" messages, and copy the exception to me.

**Context menu doesn't appear on long-press**

`.contextMenu` requires iOS 17+ for `Section` headers inside the menu. If you're targeting an older simulator runtime, the menu shows but without section headers. Not a bug, just looks different.

**Code signing error on build**

Personal Team signing works fine, but only if you've added an Apple ID in Xcode → Settings → Accounts. If the build errors with "Signing requires a development team", go do Step 3 again.

**"iPhone 15 Pro" simulator doesn't exist in the picker**

Xcode → Settings → Platforms → add iOS 17.0 or later runtime. Long download, one-time cost.

---

## When you're done exploring

Drop me a note with:

- A one-line verdict: does the Mushaf look like Golden Quran now, or is something still off?
- A screenshot of page 1 and page 2 if possible (simulator: File → Save Screen, then drag into the chat).
- Any smoke-test items that failed.

Once that's confirmed, the next coding priority is **Fihris** (the surah list sheet, #22) — that's how you'll navigate between surahs in the simulator without swiping 600 times.
