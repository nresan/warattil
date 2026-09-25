# WARATTIL 3.0.2 — Release Notes

**versionCode:** 31
**versionName:** 3.0.2
**Build date:** 2026-05-19

---

## Play Console release notes (paste into the form)

### Arabic — for "Default language" ar

```
تحسينات على مربع الشاشة الرئيسية:

• حالة قراءتك دائمًا ظاهرة — رقم الصفحة، السورة، الجزء، ومؤشّر ورد اليوم
• إذا فعّلت الأذان: يظهر عدّاد تنازليّ للصلاة القادمة (مثل «الفجر بعد ٠٣:٥٨»)
• تنسيق أكثر إحكامًا — ارتفاع أقل، مساحة أقل ضائعة
• معالجة بقاء العدّاد معلّقًا على الصلاة السابقة لأكثر من عشرين دقيقة بعد الأذان
```

### English — fallback if you add an `en` localization

```
Home-screen widget improvements:

• Your reading state is now always visible — page number, surah, juz, and the daily wird indicator
• When Azan is enabled: a live countdown to the next prayer appears (e.g. "Fajr in 03:58")
• Tighter layout — less height, less wasted space
• Fixed the "stuck on previous prayer for 20+ minutes" bug after Azan fires
```

---

## Build the signed AAB

### Option A — Android Studio (GUI)

1. **Build** menu → **Generate Signed App Bundle / APK...**
2. Select **Android App Bundle** → Next
3. Keystore path: `warattil_new_upload.jks` (the real upload key — alias `upload`, SHA-1 must start with `75:50:B1:91…`)
4. Enter keystore + key passwords
5. Build variant: `release`, signature versions: V2 + V3
6. Click **Create**
7. AAB lands at `app/release/app-release.aab`

### Option B — Terminal (faster if comfortable)

```bash
cd ~/AndroidStudioProjects/WarattilV3
./gradlew bundleRelease
```

AAB ends up at `app/build/outputs/bundle/release/app-release.aab`.

Verify the SHA-1 before uploading:

```bash
keytool -printcert -jarfile app/build/outputs/bundle/release/app-release.aab | grep SHA1
```

Must equal the SHA-1 of `warattil_v3_upload.jks`'s `upload` alias (Play Console will reject if not).

---

## Upload to Play Console

1. Play Console → ورتّل listing → **Production** → **Create new release**
2. **Upload** the AAB
3. Paste the Arabic release notes above into the release notes field
4. **Rollout %:** start at **20%** staged rollout (cautious — Azan-related changes touch alarms and SharedPreferences) OR **100%** if you trust the change (it has been hand-tested on your device)
5. **Review release** → **Start rollout**

Approval usually within a few hours (sometimes minutes for established listings with no policy flags). After approval, the rollout begins automatically.

---

## Post-release verification

Once Play Console says "Available" (typically 2–4 hours after rollout start):

- [ ] Open the Play Store on a different device, search «ورتّل» — should show version 3.0.2 as the latest
- [ ] Update your test phone via Play Store (just to verify the OTA path works, not just the local install)
- [ ] On the home-screen widget: confirm reading state shows + countdown line appears when Azan is enabled
- [ ] Wait until the next prayer fires; verify the chronometer correctly flips back to BEFORE_PRAYER for the next prayer within 20 minutes (no "stuck on previous prayer" regression)

---

## If anything looks wrong post-release

You can **halt the rollout** in Play Console → Production → click the active rollout → **Halt rollout**. This stops the % from increasing further (existing installers stay on the new version). Bug-fix release would be 3.0.3 / versionCode 32.

Or **roll back** by uploading the previous AAB (3.0.1 / versionCode 30) as a NEW release with a higher versionCode (32, 33, ...) but the older codebase — Play doesn't allow downgrades by versionCode, only by code identity. Talk to me if you need to do this — it's rare but doable.
