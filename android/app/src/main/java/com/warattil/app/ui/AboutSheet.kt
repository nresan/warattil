package com.warattil.app.ui

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.R
import com.warattil.app.core.ShareUtil

// =============================================================================
// AboutSheet — «عن التطبيق»
//
// A calm, single-scroll introduction inspired by the printed Madinah Mushaf's
// opening pages (الرواية، المصادر، الاصطلاحات). Four short sections:
//
//   ١ · الرواية والنصّ      — provenance & text authority
//   ٢ · الرسالة             — Sadaqah Jariyah, quietly stated
//   ٣ · شكر وتقدير          — scholarly lineage
//   ٤ · للتواصل             — contact email for corrections/suggestions
//
// The six-entry affordance guide («دليل الاستخدام») that used to live here
// was extracted to its own sheet (UsageGuideSheet) in April 2026 — the
// About sheet was doing three jobs (identity, tutorial, utility) and the
// tutorial was the one users *returned* to. Keeping it separate lets About
// stay calm (identity + mission + thanks) and makes the guide discoverable
// on demand from the overflow menu.
//
// Visual: cream background, Mushaf Green headings, gold hairlines between
// sections. No floral frames, no emoji — Uthmanic body font for Arabic prose,
// FontFamily.Default for numerals so digits render cleanly.
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutSheet(
    font     : QuranFontInfo,
    theme    : ThemeColors,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = theme.background) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 620.dp)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 22.dp, vertical = 8.dp)
            ) {
                // ── ١ · Basmala (FIRST) ────────────────────────────────────────
                // Full Basmala in the Uthmanic script at 22sp in Mushaf gold,
                // framed by restrained floral flourishes above and below.
                // No ayah brackets here — the Basmala opens a surah; it is
                // not an ayah in itself by Madinah-Mushaf convention.
                Text(
                    text       = "❁  ❊  ❁",
                    color      = theme.gold.copy(alpha = 0.55f),
                    fontSize   = 11.sp,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text       = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ",
                    color      = theme.gold,
                    fontSize   = 22.sp,
                    fontFamily = font.family,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth(),
                    style      = TextStyle(
                        textDirection = TextDirection.Rtl,
                        lineHeight    = 36.sp
                    )
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text       = "❁  ❊  ❁",
                    color      = theme.gold.copy(alpha = 0.55f),
                    fontSize   = 11.sp,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth()
                )

                // Gold hairline separator between Basmala and the brand mark.
                Spacer(Modifier.height(10.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(10.dp))

                // ── ٢ · Warattil seal + source ayah ────────────────────────────
                // Circular launcher icon (reduced to 72 dp to tighten vertical
                // rhythm) followed directly by the ayah it is named after.
                // No repeated «ورتِّل» label — the logo already carries that mark.
                Box(
                    modifier         = Modifier.fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        painter            = painterResource(id = R.drawable.ic_warattil_logo),
                        contentDescription = "Warattil",
                        contentScale       = ContentScale.Crop,
                        modifier           = Modifier
                            .size(72.dp)
                            .clip(CircleShape)
                            .border(
                                width = 0.75.dp,
                                color = theme.gold.copy(alpha = 0.45f),
                                shape = CircleShape
                            )
                    )
                }
                Spacer(Modifier.height(10.dp))

                // Source ayah — the ornate parens (U+FD3E ﴾ / U+FD3F ﴿) are
                // Bidi-mirrored glyphs; embedding them inside a single RTL
                // Text made them flip outward.  We render each bracket in its
                // own Text with textDirection = Ltr (so the font never
                // mirrors them) and rely on the outer RTL Row to place them
                // correctly: first child on the visual right.
                Row(
                    modifier              = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment     = Alignment.CenterVertically
                ) {
                    // Right-visual bracket — native glyph opens LEFT → toward text ✓
                    Text(
                        text       = "﴿",
                        color      = theme.gold,
                        fontSize   = 22.sp,
                        fontFamily = font.family,
                        style      = TextStyle(textDirection = TextDirection.Ltr)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text       = "وَرَتِّلِ ٱلْقُرْءَانَ تَرْتِيلًا",
                        color      = theme.text,
                        fontSize   = 18.sp,
                        fontFamily = font.family,
                        style      = TextStyle(
                            textDirection = TextDirection.Rtl,
                            lineHeight    = 30.sp
                        )
                    )
                    Spacer(Modifier.width(6.dp))
                    // Left-visual bracket — native glyph opens RIGHT → toward text ✓
                    Text(
                        text       = "﴾",
                        color      = theme.gold,
                        fontSize   = 22.sp,
                        fontFamily = font.family,
                        style      = TextStyle(textDirection = TextDirection.Ltr)
                    )
                }
                Spacer(Modifier.height(2.dp))
                Text(
                    text       = "سورة المزمّل ـ الآية ٤",
                    color      = theme.gold.copy(alpha = 0.75f),
                    fontSize   = 11.sp,
                    fontFamily = FontFamily.Default,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth(),
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )

                // Closing gold hairline before the body sections begin.
                Spacer(Modifier.height(12.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(14.dp))

                // ── ١ · الرواية والنصّ ─────────────────────────────────────────
                SectionHeading("الرواية والنصّ", font, theme)
                SectionBody(
                    "يُعرض القرآن الكريم في هذا التطبيق برواية حفص بن سليمان عن " +
                    "عاصم بن أبي النَّجود الكوفي، وهي الرواية المعتمدة في المصحف " +
                    "المدني الذي يطبعه مجمع الملك فهد لطباعة المصحف الشريف.",
                    font, theme
                )
                Spacer(Modifier.height(6.dp))
                SectionBody(
                    "كلّ حدود الصفحات الـ٦٠٤ مطابقة للمصحف المدني، حرفًا بحرف. " +
                    "النصّ والخطّ مصدرهما مجمع الملك فهد لطباعة المصحف " +
                    "الشريف بالمدينة المنورة.",
                    font, theme
                )
                Spacer(Modifier.height(18.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(18.dp))

                // ── ٢ · الرسالة ───────────────────────────────────────────────
                SectionHeading("الرسالة", font, theme)
                SectionBody(
                    "نَسأل الله أن يجعل هذا التطبيق صدقةً جاريةً لكل من شارك فيه " +
                    "ولكل من يقرأ به. هو مجاني للجميع، بلا إعلانات، ولا يجمع " +
                    "أي بيانات شخصية، ويعمل بلا إنترنت.",
                    font, theme
                )
                Spacer(Modifier.height(18.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(18.dp))

                // ── ٣ · شكر وتقدير ────────────────────────────────────────────
                SectionHeading("شكر وتقدير", font, theme)
                SectionBody(
                    "الحمد لله على ما أعان ويسّر. ولفضيلة علماء الأمة الذين نقلوا " +
                    "الرسم العثماني والضبط وعدّ الآي جزيل الشكر، ولمجمع الملك " +
                    "فهد لطباعة المصحف الشريف على اعتماده الذي تَستندُ إليه هذه " +
                    "النسخة نصًّا وخطًّا، ولمشروع «تنزيل» على بيانات فهرسة الصفحات.",
                    font, theme
                )
                Spacer(Modifier.height(18.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(18.dp))

                // ── ٤ · للتواصل ───────────────────────────────────────────────
                // A positive invitation to send comments and suggestions for
                // app enhancement. Deliberately avoids "if you find a mistake"
                // framing — the Mushaf text is sourced from KFGQPC and the
                // contact line should reinforce (not undermine) that trust.
                // The email line is clickable (launches the user's email
                // client via a mailto: intent) and the runCatching wrapper
                // silently absorbs ActivityNotFoundException on devices
                // without a configured mail app — the email remains visible
                // and copyable either way.
                SectionHeading("للتواصل", font, theme)
                SectionBody(
                    "نرحِّب بملاحظاتك واقتراحاتك لتطوير التطبيق، " +
                    "على البريد الإلكتروني:",
                    font, theme
                )
                Spacer(Modifier.height(6.dp))
                val context = LocalContext.current
                Text(
                    text       = "contact@warattil.org",
                    color      = theme.gold,
                    fontSize   = 14.sp,
                    fontFamily = FontFamily.Default,
                    fontWeight = FontWeight.Medium,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier
                        .fillMaxWidth()
                        .clickable {
                            runCatching {
                                context.startActivity(
                                    Intent(Intent.ACTION_SENDTO).apply {
                                        data = Uri.parse("mailto:contact@warattil.org")
                                    }
                                )
                            }
                        },
                    style      = TextStyle(
                        textDirection  = TextDirection.Ltr,
                        textDecoration = TextDecoration.Underline
                    )
                )

                // ── Website line ──────────────────────────────────────────────
                // Second reach-out channel under the same "للتواصل" heading —
                // the email is for 1:1 feedback, the website is for browsing
                // the project's public face. Display is the bare host
                // ("warattil.org") because it reads cleaner than the full URL
                // and matches how domains are spoken aloud; the click target
                // carries the https:// scheme so ACTION_VIEW resolves to a
                // browser rather than falling through to a host-picker.
                // runCatching absorbs ActivityNotFoundException on the
                // extremely rare device with no browser installed.
                Spacer(Modifier.height(10.dp))
                SectionBody(
                    "وللاطّلاع على المزيد حول المشروع، موقعنا على الإنترنت:",
                    font, theme
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text       = "www.warattil.org",
                    color      = theme.gold,
                    fontSize   = 14.sp,
                    fontFamily = FontFamily.Default,
                    fontWeight = FontWeight.Medium,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier
                        .fillMaxWidth()
                        .clickable {
                            runCatching {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW).apply {
                                        data = Uri.parse("https://www.warattil.org")
                                    }
                                )
                            }
                        },
                    style      = TextStyle(
                        textDirection  = TextDirection.Ltr,
                        textDecoration = TextDecoration.Underline
                    )
                )

                Spacer(Modifier.height(22.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(18.dp))

                // ── المصدر المفتوح ────────────────────────────────────────────
                // WARATTIL is published as a صدقة جارية: the complete source
                // of both the Android and iOS apps is public on GitHub under
                // the MIT licence so anyone can study it, build it, or carry
                // it forward.  Same clickable-link pattern as the website
                // line above.
                SectionHeading("المصدر المفتوح", font, theme)
                SectionBody(
                    "ورتّل صدقةٌ جارية — الشيفرة المصدرية الكاملة للتطبيق " +
                    "(أندرويد وآيفون) متاحة للجميع مجانًا برخصة MIT، " +
                    "لمن أراد أن يتعلّم منها أو يبني عليها أو يُكمل المسيرة:",
                    font, theme
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text       = "github.com/nresan/warattil",
                    color      = theme.gold,
                    fontSize   = 14.sp,
                    fontFamily = FontFamily.Default,
                    fontWeight = FontWeight.Medium,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier
                        .fillMaxWidth()
                        .clickable {
                            runCatching {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW).apply {
                                        data = Uri.parse("https://github.com/nresan/warattil")
                                    }
                                )
                            }
                        },
                    style      = TextStyle(
                        textDirection  = TextDirection.Ltr,
                        textDecoration = TextDecoration.Underline
                    )
                )

                Spacer(Modifier.height(22.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(18.dp))

                // ── ٥ · شارك ورتّل ───────────────────────────────────────────
                // Static QR encoding the Play Store listing URL.  Covers the
                // in-person sharing case — halaqa teacher showing it to the
                // study circle, parent at a family majlis, imam after prayer —
                // that the overflow menu's share-sheet CTA does not reach:
                // proximity, not messaging.
                //
                // The PNG itself is charcoal-on-cream so it remains self-
                // contained on both Heritage-Cream and Dark themes; it looks
                // like a small cream card carrying the glyph on dark skins
                // rather than disappearing into the background.  Error
                // correction level H (~30%) keeps it scannable even if a
                // finger partially occludes a corner.
                SectionHeading("شارك ورتّل", font, theme)
                SectionBody(
                    "اعرض هذا الرمز لمن حولك، يمسحه بكاميرا الهاتف فيصل " +
                    "إلى متجر التطبيق مباشرة.",
                    font, theme
                )
                Spacer(Modifier.height(14.dp))
                Box(
                    modifier         = Modifier.fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    // Tap-to-share (BLUEPRINT §11.6 — April 2026): decoding
                    // R.drawable.warattil_qr via BitmapFactory rather than
                    // going through the Painter / ImageBitmap round-trip
                    // keeps the share path resource-bucket-agnostic — we
                    // always hand the share chooser the *highest-fidelity*
                    // PNG from drawable-nodpi/, not whatever the current
                    // Density picked for display.  runCatching guards against
                    // a missing asset (shouldn't happen — warattil_qr is
                    // pinned at -nodpi) so a decode failure silently falls
                    // through without crashing the sheet.
                    Image(
                        painter            = painterResource(id = R.drawable.warattil_qr),
                        contentDescription = "اضغط لمشاركة رمز QR للوصول إلى ورتّل على متجر Google Play",
                        modifier           = Modifier
                            .size(180.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .border(
                                width = 0.75.dp,
                                color = theme.gold.copy(alpha = 0.45f),
                                shape = RoundedCornerShape(12.dp)
                            )
                            .clickable {
                                runCatching {
                                    val bmp = BitmapFactory.decodeResource(
                                        context.resources,
                                        R.drawable.warattil_qr
                                    )
                                    if (bmp != null) ShareUtil.shareQrCode(context, bmp)
                                }
                            }
                    )
                }
                // Hadith caption — anchors the share in its Islamic framing
                // rather than treating this as growth-marketing chrome.
                Spacer(Modifier.height(10.dp))
                Text(
                    text       = "«من دلَّ على خير فله مثل أجر فاعله»",
                    color      = theme.gold.copy(alpha = 0.75f),
                    fontSize   = 11.sp,
                    fontFamily = FontFamily.Default,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth(),
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )

                Spacer(Modifier.height(22.dp))
                GoldHairline(theme)
                Spacer(Modifier.height(14.dp))

                // ── Colophon ──────────────────────────────────────────────────
                // FontFamily.Default here too — the version decimal «٢٫٠» and
                // the © symbol render as ornamental circles under the
                // Uthmanic font.
                Text(
                    text       = "ورتِّل — الإصدار ٣٫١",
                    color      = theme.text.copy(alpha = 0.45f),
                    fontSize   = 11.sp,
                    fontFamily = FontFamily.Default,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth(),
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text       = "© ٢٠٢٦ — مفتوح المصدر برخصة MIT",
                    color      = theme.text.copy(alpha = 0.35f),
                    fontSize   = 10.sp,
                    fontFamily = FontFamily.Default,
                    textAlign  = TextAlign.Center,
                    modifier   = Modifier.fillMaxWidth(),
                    style      = TextStyle(textDirection = TextDirection.Rtl)
                )
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

// ── Shared building blocks ─────────────────────────────────────────────────
// These helpers are declared `internal` so UsageGuideSheet (same package)
// can reuse them without duplication. GuideEntry in particular is only
// called by UsageGuideSheet now, but keeping the block here keeps the
// helpers close to their original author-context; extract to a dedicated
// file if a third sheet ever needs them.
//
// Arabic prose in these sheets — section headings, body paragraphs, guide
// lines — is rendered with FontFamily.Default (the system Arabic font).
// The Uthmanic Mushaf font is reserved for Qur'anic text (Basmala, ayah)
// because it applies ayah-badge glyph substitution that mangles Arabic
// digits ("٦٠٤" → two ornament circles) and punctuation (commas/periods
// → strange rounds) when used on ordinary prose.

@Composable
internal fun SectionHeading(
    title: String,
    font : QuranFontInfo,
    theme: ThemeColors
) {
    Text(
        text       = title,
        color      = theme.accent,
        fontSize   = 15.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.Default,
        textAlign  = TextAlign.Center,
        modifier   = Modifier.fillMaxWidth().padding(bottom = 10.dp),
        style      = TextStyle(textDirection = TextDirection.Rtl)
    )
}

@Composable
internal fun SectionBody(
    text : String,
    font : QuranFontInfo,
    theme: ThemeColors
) {
    Text(
        text       = text,
        color      = theme.text,
        fontSize   = 14.sp,
        fontFamily = FontFamily.Default,
        modifier   = Modifier.fillMaxWidth(),
        style      = TextStyle(
            textDirection = TextDirection.Rtl,
            textAlign     = TextAlign.Justify,
            lineHeight    = 24.sp
        )
    )
}

// Slot-based guide entry — the `icon` slot lets callers pass either a
// Material ImageVector (via Icon(Icons.Default.X, ...)) or our custom
// VectorDrawable painter (via Icon(painter = painterResource(R.drawable.ic_lawh_hifz), ...)),
// since the old ImageVector parameter couldn't accommodate both.
@Composable
internal fun GuideEntry(
    title: String,
    body : String,
    font : QuranFontInfo,
    theme: ThemeColors,
    icon : @Composable () -> Unit
) {
    Row(
        modifier              = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment     = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Medallion — soft gold circle holding the caller's affordance glyph.
        // Slightly larger than the old 28dp to balance the now two-line text
        // block on the right.
        Box(
            modifier         = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(theme.gold.copy(alpha = 0.10f)),
            contentAlignment = Alignment.Center
        ) {
            icon()
        }
        // Two-tier text: bold Mushaf-green title, then the descriptive body.
        Column(modifier = Modifier.weight(1f).padding(top = 2.dp)) {
            Text(
                text       = title,
                color      = theme.accent,
                fontSize   = 14.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Default,
                style      = TextStyle(
                    textDirection = TextDirection.Rtl,
                    textAlign     = TextAlign.Start
                )
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text       = body,
                color      = theme.text,
                fontSize   = 13.sp,
                fontFamily = FontFamily.Default,
                style      = TextStyle(
                    textDirection = TextDirection.Rtl,
                    textAlign     = TextAlign.Start,
                    lineHeight    = 22.sp
                )
            )
        }
    }
}

@Composable
internal fun GoldHairline(theme: ThemeColors) {
    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        HorizontalDivider(
            color     = theme.gold.copy(alpha = 0.35f),
            thickness = 0.5.dp,
            modifier  = Modifier.fillMaxWidth(0.6f)
        )
    }
}
