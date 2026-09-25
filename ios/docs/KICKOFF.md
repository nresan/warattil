# WARATTIL iOS — Kickoff Status

> **⚠ Historical document (2026-04-19 snapshot).** Most "not done yet"
> items below have since been completed (Xcode project, SwiftUI views,
> data layer, QCF rendering, long-press context menu). For a current
> view of what's in the project and how to run it, see
> **[`FIRST_LAUNCH.md`](FIRST_LAUNCH.md)** and recent git history.
> This file is kept for the decision record in §13.

Companion to `BLUEPRINT.md`. Tracks the ten open decisions from §13 plus the environment work that must be done before Xcode is useful.

Last updated: 2026-04-19.

---

## Environment

| Item | Status | Notes |
|------|--------|-------|
| Mac hardware | **OK** | MacBook Air 13", M4, 16 GB RAM. Running macOS Tahoe 26.4.1. |
| Test iPhone | **OK** | iPhone 15 Pro Max on iOS 26.4.1, 111 GB free. |
| Mac free disk | **TIGHT** | 41.33 GB free of 245.11 GB. Xcode + simulators need ~50 GB. Clean up more before installing Xcode. |
| Xcode installed | **PENDING CHECK** | Open Spotlight (Cmd+Space) → type "Xcode". If it opens, report the version under Xcode → About Xcode. If not, install from the Mac App Store after freeing disk space. |
| Apple Developer Program | **NOT STARTED — critical path** | Nasser has no Apple developer account. Enrollment ($99 USD/year, individual) takes 24 hrs – 1 week for identity verification. Blocks TestFlight and App Store submission (Phase 15). Does NOT block Phases 1–14 — free "Personal Team" signing in Xcode works for on-device debugging. **Start today.** |

---

## Decisions from §13

| # | Question | Status | Resolution |
|---|----------|--------|------------|
| 1 | Mac with Xcode 15+? | Partial | Mac confirmed; Xcode install status pending Spotlight check. |
| 2 | Apple Developer Program active? | **Open / blocking** | Not enrolled. Start enrollment ASAP. |
| 3 | iOS minimum version | **Open — awaiting Nasser** | Blueprint said iOS 16. Given Nasser's phone is on iOS 26.4.1, recommending iOS 17.0 floor (cleaner APIs, negligible device-reach cost by April 2026). Default on hold until Nasser weighs in. |
| 4 | iPad support | Settled | iPhone-only for v1. iPad deferred to v1.1+. |
| 5 | Repo structure | Settled (tentative) | Separate iOS repo recommended. For now, the iOS code lives under `ios/` in the existing monorepo as a working area; when ready to cut a standalone repo we'll extract. |
| 6 | Widget / Complications in v1 | Settled | No. Deferred to post-v1. |
| 7 | Analytics | Settled | None. Zero tracking, zero third-party SDKs. |
| 8 | Dark mode behaviour | Settled | Manual theme cycle (Heritage → Dark → Sepia), NOT tied to iOS system Dark Mode. Matches Android. |
| 9 | Languages | Settled | Arabic-only UI. Confirmed by Nasser ("Arabic-speaking Muslims only"). English for store-listing discoverability only. |
| 10 | App Store listing copy | Pending | Draft Arabic (mirroring Play Store listing since Dec 2025) + English together before submission. |

---

## What's been done automatically in this session

See `../README.md` for the file-by-file inventory. Summary:

- iOS project skeleton created under `ios/`.
- Shared assets copied into `ios/Warattil/Resources/`: `quran_v2.db`, `quran_metadata.xml` (renamed from the Android file), and all 15 font files.
- Ported: `WarattilConstants.swift`, `Ayah.swift`, `QuranMetadata.swift` (incl. Eastern-digit helper), `MetadataParser.swift`, `ShareUtil.swift`.
- `Info.plist` and `PrivacyInfo.xcprivacy` drafted.
- `Package.swift` created so parser + share-util logic can be unit-tested without Xcode.
- Boundary parity fixture generated from Android XML — `ios/WarattilTests/Fixtures/page_boundaries.json` (604 entries) and `juz_boundaries.json` (30 entries).
- XCTest target `MetadataParserTests.swift` written — will run when Xcode + SwiftPM are available on the Mac.

---

## What Nasser needs to do next (manual steps)

### 1. Free Mac disk space

Target: at least 50 GB free. Options:

- Apple menu → About This Mac → More Info → Storage Settings → **Manage** — sort by size, delete what you don't need.
- Empty Trash (Finder → Empty Trash).
- Delete old iPhone backups from Finder (if any).
- Remove large Downloads you don't remember.

Current free: 41.33 GB. Need: ≥50 GB.

### 2. Start Apple Developer enrollment (critical path)

1. Go to https://developer.apple.com/programs/enroll/ on Mac.
2. Sign in with the Apple ID you want tied to WARATTIL (or create one at https://appleid.apple.com if you don't have one).
3. Enable two-factor authentication on that Apple ID — Apple will require it.
4. Choose **Individual** enrollment (cheaper, faster, no D-U-N-S number needed) unless you've incorporated a legal entity — in which case Organization is correct.
5. Pay $99 USD (annual).
6. Wait for the verification email. Can take 24 hours to one full week. You will NOT be able to upload to TestFlight until this completes.

This runs in parallel with everything else. Don't block on it.

### 3. Check Xcode status

Open Spotlight (⌘+Space) and type `Xcode`.

- **If it opens:** Xcode → About Xcode → copy the version number, reply here.
- **If Spotlight finds nothing:** Xcode isn't installed. Open the Mac App Store, search "Xcode", install (≥15 GB download, ~40 GB on disk after first launch). Requires disk space from step 1.

### 4. Confirm iOS minimum version

iOS 17.0 is my default recommendation. If you want different, tell me before I start writing SwiftUI views that use iOS-17-only APIs like `@Observable`.

---

## What's NOT done yet (by design — waits for Xcode + your decisions)

- Xcode project file (`.xcodeproj`) — created in Xcode itself, not by hand.
- SwiftUI views (`MushaFScreen`, `MushaFHeader`, `MushaFFooter`, `MushaFBody`, `AyahActionBar`, sheets).
- GRDB setup and `QuranRepository.swift`.
- Font PostScript name verification (need Font Book on the Mac to confirm `"KFGQPCUthmanicScriptHAFS"` is actually what the OTF registers as — SwiftUI fails silently if this string is wrong).
- App Icon assets and LaunchScreen storyboard.
- Any App Store Connect work (blocked on enrollment).
