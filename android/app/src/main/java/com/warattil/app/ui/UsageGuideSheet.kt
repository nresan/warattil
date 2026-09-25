package com.warattil.app.ui

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

// =============================================================================
// UsageGuideSheet — «دليل الاستخدام»
//
// Renders a ModalBottomSheet containing a full-height WebView that loads
// app/src/main/assets/help.html — a self-contained RTL Arabic guide covering
// all app features: القراءة، البحث، الإشارات، الورد اليومي، الحفظ، معاني
// الآيات، تذكير الصلاة، المشاركة، المظاهر، وضع المطالعة.
//
// The HTML file carries its own WARATTIL design tokens and Amiri/IBM Plex Sans
// Arabic web-fonts, so the sheet is visually self-sufficient and independent
// of the Compose theme passed in.  (The `theme` parameter is still accepted
// to keep the call-site signature stable and for the sheet container colour.)
//
// WebView touch events are allowed to propagate normally — the WebView owns
// vertical scrolling within the sheet, and the ModalBottomSheet drag handle
// at the top lets the user dismiss as usual.
// =============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UsageGuideSheet(
    font     : QuranFontInfo,          // kept for call-site compatibility
    theme    : ThemeColors,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor   = theme.background,
        sheetState       = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        // The sheet expands to ~90% of screen height; the WebView scrolls
        // within that space, so the user never sees a bouncing native list
        // fighting with a nested WebView scroller.
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.90f),
            factory  = { ctx ->
                WebView(ctx).apply {
                    webViewClient = WebViewClient()
                    settings.apply {
                        javaScriptEnabled    = false   // static HTML, no JS needed
                        domStorageEnabled    = false
                        allowFileAccess      = true    // needed to load from assets://
                    }
                    // Transparent background so the sheet's cream colour shows
                    // through the WebView chrome before the HTML paints.
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    loadUrl("file:///android_asset/help.html")
                }
            }
        )
    }
}
