package com.warattil.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.warattil.app.core.ShareUtil
import com.warattil.app.core.WarattilConstants.Hifz
import kotlinx.coroutines.launch

// =============================================================================
// HifzCelebrationDialog
//
// Fired from MushaFScreen when MushaFViewModel emits a tier-crossing event.
// Purpose: acknowledge the milestone — not congratulate in marketing terms,
// but name it in the scholarly register (براعم الحفظ / نبتة الحفظ / حافظ /
// شارفت على الختم / حافظ للقرآن الكريم) and point at the next milestone so
// the reader knows where the journey continues.
//
// Aesthetic — kuttāb:
//   • Gold border + cream background (matches Warattil's brand)
//   • Single large bloom glyph — shared with the heatmap flowers — over a
//     Mushaf-Green disc, framing the moment with the same visual vocabulary
//     the user already associates with juz completion.
//   • No "you earned X!" language — the phrasing is Quranic in register
//     ("بارك الله فيك", "سدّد خطاك").
//
// Actions:
//   • الحمد لله — primary, dismisses.
//   • شارك فرحتك — secondary, captures the dialog content via graphicsLayer
//     and shares it as a PNG via ShareUtil.shareHifzMilestone.  Earlier
//     this fell through to the App-Invite text share, which sent generic
//     invite copy instead of the actual milestone card (Nasser 2026-04-27).
//
// Capture region — Heritage-locked
// --------------------------------
// The captured PNG must look celebratory regardless of the user's active
// theme.  All colors INSIDE the captured Box are pinned to Heritage cream
// + charcoal + Heritage gold (same lock pattern DailyReadingShareCard,
// HifzHeatmapTab, and AppInviteShareCard use).  Background is on the
// inner Column (not the outer Box modifier) so it ends up baked into
// the recorded layer — otherwise the PNG ships with transparent
// background and dark-mode chat bubbles bleed through.  See task #40
// for the full diagnosis.
// =============================================================================

@Composable
fun HifzCelebrationDialog(
    tier     : Int,
    juzCount : Int,
    font     : QuranFontInfo,
    theme    : ThemeColors,
    onDismiss: () -> Unit
) {
    val tierLabel = Hifz.hifzTierLabel(tier)
    val nextJuz   = Hifz.nextTierJuzThreshold(tier)   // null for tier 6 (khatma)
    val nextLabel = nextJuz?.let { Hifz.hifzTierLabel(tier + 1) }

    // Honorific / encouragement varies slightly by tier so the final
    // celebration (tier 6, khatma) lands with appropriate gravity.
    val honorific = when (tier) {
        6    -> "بارك الله لك في حفظك · اللهم اجعل القرآن ربيع قلبه"
        5    -> "شارفتَ على الختم · اللهم يسّر وأتمّ"
        4    -> "بارك الله فيك · سدّد الله خطاك"
        3    -> "بارك الله فيك · ثبّت الله حفظك"
        2    -> "نبتة طيبة بإذن الله · ثبّت الله خطاك"
        1    -> "بدايةٌ مباركة · جعل الله لك في كل آية أجراً"
        else -> "بارك الله فيك"
    }

    // Heritage-locked palette for the captured PNG.  The dialog's outer
    // chrome (AlertDialog container, buttons) still uses the live `theme`
    // so the in-app overlay feels native to the user's mode — only the
    // captured card is fixed to Heritage.
    val shareTheme = WarattilTheme.Heritage

    val graphicsLayer = rememberGraphicsLayer()
    val context       = LocalContext.current
    val scope         = rememberCoroutineScope()

    AlertDialog(
        onDismissRequest  = onDismiss,
        containerColor    = theme.background,
        titleContentColor = Hifz.HIFZ_GOLD,
        textContentColor  = theme.text,
        shape             = RoundedCornerShape(18.dp),
        // Title is folded INTO the captured content below — separating it
        // into the AlertDialog.title slot would split the share into two
        // visual blocks Material spaces independently and keep the title
        // out of the captured region.  Setting title = null gives the
        // dialog one coherent capturable card.
        text = {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                // Captured region — graphicsLayer records every draw call
                // inside drawContent.  Background lives on the inner
                // Column so it's part of drawContent (and therefore baked
                // into the PNG); putting it on this outer Box would be
                // painted by the modifier chain BEFORE drawContent and
                // would ship as transparent on the PNG.
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .drawWithContent {
                            graphicsLayer.record { this@drawWithContent.drawContent() }
                            drawLayer(graphicsLayer)
                        }
                ) {
                    Column(
                        modifier              = Modifier
                            .fillMaxWidth()
                            .background(shareTheme.background, RoundedCornerShape(12.dp))
                            .padding(horizontal = 16.dp, vertical = 18.dp),
                        horizontalAlignment   = Alignment.CenterHorizontally,
                        verticalArrangement   = Arrangement.spacedBy(12.dp)
                    ) {
                        // ── Header line (was the AlertDialog.title slot) ────
                        Text(
                            "مبارك! بلغتَ مرحلةً جديدة",
                            fontWeight = FontWeight.Bold,
                            fontSize   = 16.sp,
                            fontFamily = font.family,
                            textAlign  = TextAlign.Center,
                            color      = Hifz.HIFZ_GOLD,
                            modifier   = Modifier.fillMaxWidth(),
                            style      = TextStyle(textDirection = TextDirection.Rtl)
                        )

                        // ── Bloom hero — mushaf-green disc with a single gold
                        //    flower glyph.  Same visual vocabulary as heatmap
                        //    juz-completion, so the reader recognises the motif.
                        Box(
                            modifier = Modifier
                                .size(86.dp)
                                .clip(RoundedCornerShape(50))
                                .background(Hifz.HEATMAP_FULL)
                                .border(
                                    1.5.dp,
                                    Hifz.HIFZ_GOLD,
                                    RoundedCornerShape(50)
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            CelebrationFlower(
                                petal  = Hifz.FLOWER_PETAL,
                                center = Hifz.FLOWER_CENTER,
                                modifier = Modifier.size(68.dp)
                            )
                        }

                        // ── Tier name — the hero of this dialog ─────────────
                        Text(
                            tierLabel,
                            fontSize   = 22.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = font.family,
                            color      = Hifz.HIFZ_GOLD,
                            textAlign  = TextAlign.Center
                        )

                        // ── Juz milestone factually stated (Eastern-Arabic) ─
                        Text(
                            "${juzCount.toArabicDigits()} من ${30.toArabicDigits()} جزءاً بإذن الله",
                            fontSize   = 13.sp,
                            fontFamily = font.family,
                            color      = shareTheme.text.copy(alpha = 0.75f),
                            textAlign  = TextAlign.Center
                        )

                        // ── Honorific / du'a line ──────────────────────────
                        Text(
                            honorific,
                            fontSize   = 13.sp,
                            fontFamily = font.family,
                            color      = shareTheme.text.copy(alpha = 0.85f),
                            textAlign  = TextAlign.Center,
                            modifier   = Modifier.padding(horizontal = 4.dp)
                        )

                        // ── Next-goal pointer (omitted for khatma) ─────────
                        if (nextJuz != null && nextLabel != null) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 4.dp)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(Hifz.HIFZ_GOLD.copy(alpha = 0.08f))
                                    .border(
                                        0.75.dp,
                                        Hifz.HIFZ_GOLD.copy(alpha = 0.4f),
                                        RoundedCornerShape(10.dp)
                                    )
                                    .padding(horizontal = 12.dp, vertical = 8.dp)
                            ) {
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text(
                                        "المرحلة القادمة",
                                        fontSize   = 11.sp,
                                        fontFamily = font.family,
                                        color      = shareTheme.text.copy(alpha = 0.55f)
                                    )
                                    Text(
                                        "$nextLabel · عند ${nextJuz.toArabicDigits()} جزءاً",
                                        fontSize   = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        fontFamily = font.family,
                                        color      = Hifz.HIFZ_GOLD
                                    )
                                }
                            }
                        }

                        // ── Attribution strip (captured) ───────────────────
                        //   Same self-branding pattern as the other share
                        //   surfaces.  Subtle so it doesn't compete with
                        //   the milestone visually but always present in
                        //   the PNG so a receiver knows the source.
                        Spacer(Modifier.height(2.dp))
                        Row(
                            modifier              = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment     = Alignment.CenterVertically
                        ) {
                            Text(
                                "ورتّل",
                                color      = Hifz.HIFZ_GOLD,
                                fontSize   = 11.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = font.family
                            )
                            Text(
                                "  ·  warattil.org/get",
                                color      = shareTheme.text.copy(alpha = 0.45f),
                                fontSize   = 10.sp,
                                fontFamily = FontFamily.Default
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onDismiss,
                shape   = RoundedCornerShape(10.dp),
                colors  = ButtonDefaults.buttonColors(
                    containerColor = Hifz.HIFZ_GOLD,
                    contentColor   = Color.White
                )
            ) {
                Text(
                    "الحمد لله",
                    fontFamily = font.family,
                    fontWeight = FontWeight.SemiBold
                )
            }
        },
        dismissButton = {
            OutlinedButton(
                onClick = {
                    // Capture the recorded layer to a Bitmap and hand to
                    // ShareUtil.shareHifzMilestone.  Coroutine because
                    // toImageBitmap can be called off-main but the
                    // surrounding context is composable.
                    scope.launch {
                        val bmp = graphicsLayer.toImageBitmap().asAndroidBitmap()
                        ShareUtil.shareHifzMilestone(context, bmp)
                    }
                },
                shape   = RoundedCornerShape(10.dp),
                border  = androidx.compose.foundation.BorderStroke(
                    1.dp, Hifz.HIFZ_GOLD.copy(alpha = 0.6f)
                ),
                colors  = ButtonDefaults.outlinedButtonColors(
                    contentColor = Hifz.HIFZ_GOLD
                )
            ) {
                Text(
                    "شارك فرحتك",
                    fontFamily = font.family,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    )
}

// ── Celebration flower — larger variant of the heatmap bloom glyph ──────────
//   Same 5-petal geometry as HifzLogSheet's FlowerGlyph but self-contained so
//   the dialog does not depend on a private composable in another file.
//   Petal scale tuned for a ~68dp hero (vs. ~14dp heatmap cell): the ratios
//   are identical, so the two glyphs read as a matched pair when shown
//   together (the dialog + the heatmap).

@Composable
private fun CelebrationFlower(
    petal   : Color,
    center  : Color,
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier) {
        val cx = size.width  / 2f
        val cy = size.height / 2f
        val minSide   = kotlin.math.min(size.width, size.height)
        val petalDist = minSide * 0.26f
        val petalR    = minSide * 0.24f
        val centerR   = minSide * 0.14f
        for (i in 0 until 5) {
            val a  = (-Math.PI / 2.0 + i * 2.0 * Math.PI / 5.0).toFloat()
            val px = cx + petalDist * kotlin.math.cos(a)
            val py = cy + petalDist * kotlin.math.sin(a)
            drawCircle(color = petal, radius = petalR, center = Offset(px, py))
        }
        drawCircle(color = center, radius = centerR, center = Offset(cx, cy))
    }
}
