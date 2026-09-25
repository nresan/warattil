package com.warattil.app.widget

import java.util.Calendar

// =============================================================================
// DailyDuaa — daily-rotating ma'thūr (prophetic) supplications for the widget.
//
// Curated to a strict rule: ONLY non-Quranic ma'thūr du'aas attributed to the
// Prophet ﷺ in authentic Sunnah sources (Bukhari, Muslim, Abu Dawud, Tirmidhi,
// Nasai, Ibn Majah).  This is intentional — the "no auto-curated Quran content"
// project rule forbids "ayah of the day"-style algorithmic surfacing of Qur'anic
// material.  Du'aas from the Sunnah are a separate category and Nasser
// specifically asked for daily rotation in the widget surface (2026-05-16).
//
// Stable within a day, different across days: indexed by Calendar.DAY_OF_YEAR
// mod N.  With ~22 entries the cycle repeats roughly every three weeks — long
// enough that the same du'aa doesn't feel repetitive, short enough that the
// reader becomes familiar with the corpus over time.
//
// Each entry is short enough to render in the widget's 2-line bottom strip
// (≤ ~80 characters incl. Arabic combining marks).  Diacritics included so the
// rendered glyphs read at proper classical pronunciation.
// =============================================================================

object DailyDuaa {

    private val DUAAS = listOf(
        "اللَّهُمَّ اكْفِنِي بِحَلَالِكَ عَنْ حَرَامِكَ، وَأَغْنِنِي بِفَضْلِكَ عَمَّنْ سِوَاكَ",
        "اللَّهُمَّ أَعِنِّي عَلَى ذِكْرِكَ وَشُكْرِكَ وَحُسْنِ عِبَادَتِكَ",
        "اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْهَمِّ وَالْحَزَنِ، وَالْعَجْزِ وَالْكَسَلِ",
        "اللَّهُمَّ إِنِّي أَسْأَلُكَ الْعَفْوَ وَالْعَافِيَةَ فِي الدُّنْيَا وَالْآخِرَةِ",
        "حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ، عَلَيْهِ تَوَكَّلْتُ وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ",
        "اللَّهُمَّ إِنِّي أَسْأَلُكَ عِلْمًا نَافِعًا، وَرِزْقًا طَيِّبًا، وَعَمَلًا مُتَقَبَّلًا",
        "اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنْ زَوَالِ نِعْمَتِكَ وَتَحَوُّلِ عَافِيَتِكَ",
        "اللَّهُمَّ بَارِكْ لَنَا فِيمَا رَزَقْتَنَا، وَقِنَا عَذَابَ النَّارِ",
        "اللَّهُمَّ ثَبِّتْ قَلْبِي عَلَى دِينِكَ، وَاهْدِنِي صِرَاطَكَ الْمُسْتَقِيمَ",
        "اللَّهُمَّ أَصْلِحْ لِي دِينِيَ الَّذِي هُوَ عِصْمَةُ أَمْرِي",
        "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ الْعَلِيِّ الْعَظِيمِ",
        "اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ",
        "اللَّهُمَّ يَا مُقَلِّبَ الْقُلُوبِ، ثَبِّتْ قَلْبِي عَلَى دِينِكَ",
        "اللَّهُمَّ إِنِّي أَسْأَلُكَ مِنْ فَضْلِكَ وَرَحْمَتِكَ",
        "اللَّهُمَّ إِنَّكَ عَفُوٌّ كَرِيمٌ تُحِبُّ الْعَفْوَ فَاعْفُ عَنِّي",
        "اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنْ جَهْدِ الْبَلَاءِ وَدَرَكِ الشَّقَاءِ",
        "اللَّهُمَّ آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً",
        "اللَّهُمَّ إِنِّي أَسْأَلُكَ الْهُدَى وَالتُّقَى وَالْعَفَافَ وَالْغِنَى",
        "اللَّهُمَّ طَهِّرْ قَلْبِي مِنَ النِّفَاقِ، وَعَمَلِي مِنَ الرِّيَاءِ",
        "اللَّهُمَّ ارْزُقْنِي حُبَّكَ وَحُبَّ مَنْ يَنْفَعُنِي حُبُّهُ عِنْدَكَ",
        "اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنْ عِلْمٍ لَا يَنْفَعُ، وَقَلْبٍ لَا يَخْشَعُ",
        "اللَّهُمَّ اجْعَلْ خَيْرَ عُمُرِي آخِرَهُ، وَخَيْرَ عَمَلِي خَوَاتِيمَهُ"
    )

    /**
     * The du'aa for today — stable within a day, rotates daily.  Same call
     * from two different surfaces (widget instance A and B) on the same day
     * returns the same string; tomorrow returns the next entry in the cycle.
     */
    fun forToday(now: Calendar = Calendar.getInstance()): String {
        val dayOfYear = now.get(Calendar.DAY_OF_YEAR)
        return DUAAS[dayOfYear % DUAAS.size]
    }
}
