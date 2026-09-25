package com.warattil.app.data

object QuranMetadata {
    fun getSuraName(index: Int): String = MetadataParser.getSuraName(index)
    fun getSuras(): List<SuraMetadata> = MetadataParser.getSuras()
}

fun Int.toArabicNumbers(): String {
    val arabicChars = charArrayOf('٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩')
    val str = this.toString()
    val builder = StringBuilder()
    for (ch in str) {
        if (ch.isDigit()) {
            builder.append(arabicChars[ch - '0'])
        } else {
            builder.append(ch)
        }
    }
    return builder.toString()
}

fun Int?.toArabicNumbers(): String = this?.toArabicNumbers() ?: ""
