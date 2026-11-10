<div dir="rtl" align="right">

# ورتّل — مصحف رقمي بلا إعلانات، مفتوح المصدر

**ورتّل** تطبيق مصحف للقراءة والحفظ والورد اليومي، بنص مجمع الملك فهد لطباعة المصحف الشريف وخطّه الرسمي، بلا إعلانات ولا حسابات ولا تتبّع، ويعمل بالكامل دون اتصال بالإنترنت.

هذا المستودع يحوي **الشيفرة المصدرية الكاملة** لنسختَي التطبيق:

- **أندرويد** — `android/` (Kotlin + Jetpack Compose) — [على Google Play](https://play.google.com/store/apps/details?id=com.warattil.warattilmushaf)
- **آيفون** — `ios/` (Swift + SwiftUI) — [على App Store](https://apps.apple.com/app/id6766103481)

## لماذا مفتوح المصدر؟

ورتّل **صدقةٌ جارية**. الغاية منه الثواب لا الربح، ولذلك نشرنا الشيفرة كاملةً برخصة MIT حتى:

- يتعلّم منها من أراد أن يبني تطبيقًا قرآنيًا،
- ويُصلح فيها من وجد خللًا،
- ويُكمل المسيرة من بعدنا إن توقّفنا، فلا يتوقّف التطبيق بتوقّف صاحبه.

«إذا مات ابن آدم انقطع عمله إلا من ثلاث: صدقة جارية، أو علم يُنتفع به، أو ولد صالح يدعو له».

## ما في التطبيق

- مصحف المدينة صفحةً صفحة (٦٠٤ صفحات) بخط KFGQPC الرسمي، بثلاثة أنماط: نهاري، ورقي، ليلي.
- الورد اليومي مع تذكير، وإحصاء التقدّم في الختمة.
- حلقة الحفظ: تحديد المحفوظ آيةً آية، خريطة حفظ من ٦٠٤ خلية، شارة مستوى الحافظ، ومشاركة الخريطة صورة.
- التفسير الميسّر ومعاني الكلمات الغريبة لكل آية بضغطة طويلة.
- تذكير الصلاة (الأذان) بحسب الموقع، بخيار لكل صلاة.
- البحث، الإشارات المرجعية، مشاركة الآية نصًا أو صورة، أداة الشاشة الرئيسية (أندرويد).

## البناء

**أندرويد:** افتح `android/` في Android Studio (Hedgehog أو أحدث، JDK 17) ثم `./gradlew assembleDebug`. للتوقيع للنشر انسخ `keystore.properties.example` إلى `keystore.properties` وضع مفتاحك أنت — مفتاح النشر الأصلي ليس جزءًا من المستودع.

**آيفون:** افتح `ios/Warattil/Warattil.xcodeproj` في Xcode 16 أو أحدث، اختر فريق التوقيع الخاص بك، ثم Run. لا اعتماديات خارجية.

## المساهمة

مرحبًا بكل مساهمة: تصحيح، ترجمة، تحسين أداء، أو ميزة جديدة. افتح Issue للنقاش أولًا إن كانت الميزة كبيرة. ثوابت التصميم (الألوان، الخطوط، قانون الزخم) مقفلة في `WarattilConstants` — يُرجى الاطلاع عليها قبل تغيير الواجهة.

قواعد النصّ داخل التطبيق: عربية فصيحة، بلا تسويق ولا ألعاب نقاط، وبأدب يليق بالمصحف.

## الرخصة

الشيفرة برخصة [MIT](LICENSE). نص المصحف والتفسير والخطوط ملك لأصحابها — انظر [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

للتواصل: contact@warattil.org · [warattil.org](https://www.warattil.org)

</div>

---

# WARATTIL — an ad-free, open-source Mushaf app

**WARATTIL** (ورتّل) is a Quran reading, daily-wird and memorisation app built on the King Fahd Complex (KFGQPC) Uthmani text and font. No ads, no accounts, no tracking, fully offline.

This repository holds the **complete source** of both apps:

- **Android** — `android/` (Kotlin, Jetpack Compose) — [Google Play](https://play.google.com/store/apps/details?id=com.warattil.warattilmushaf)
- **iOS** — `ios/` (Swift, SwiftUI) — [App Store](https://apps.apple.com/app/id6766103481)

## Why open source

WARATTIL is intended as a *sadaqah jariyah* — an ongoing charity whose reward outlives its author. Publishing the code under MIT means anyone can learn from it, fix it, or continue it if the original maintainers stop, so the app never dies with one person.

## Features

Madinah Mushaf page-by-page rendering (604 pages) with the official KFGQPC font in three themes; daily wird with reminders and khatmah progress; Hifz circle with ayah-level tracking, a 604-cell memorisation map, level badge and shareable map image; Tafseer al-Muyassar and rare-word glosses on long-press; location-based prayer (Azan) reminders with per-prayer modes; search, bookmarks, ayah share as text or image, home-screen widget (Android).

## Building

**Android:** open `android/` in Android Studio (JDK 17), `./gradlew assembleDebug`. For release signing copy `keystore.properties.example` to `keystore.properties` and point it at *your own* keystore — the Play upload key is not in the repo.

**iOS:** open `ios/Warattil/Warattil.xcodeproj` in Xcode 16+, set your signing team, Run. No external dependencies.

## Contributing

Issues and pull requests are welcome — fixes, translations, performance, features. Open an issue first for anything large. Design constants (colours, type scale, momentum law) are locked in `WarattilConstants`; read them before touching UI. In-app copy is classical Arabic, no marketing tone, no gamification.

## License

Code: [MIT](LICENSE). Quran text, Tafseer, dictionaries and fonts belong to their owners — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Contact: contact@warattil.org · [warattil.org](https://www.warattil.org)
