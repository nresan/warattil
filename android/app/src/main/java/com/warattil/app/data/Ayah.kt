package com.warattil.app.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "quran_text")
data class Ayah(
    @PrimaryKey
    @ColumnInfo(name = "id") val id: Int?,
    @ColumnInfo(name = "sura") val surah: Int?,
    @ColumnInfo(name = "aya") val ayah: Int?,
    @ColumnInfo(name = "text") val text: String?,
    @ColumnInfo(name = "page") val page: Int?,
    @ColumnInfo(name = "juz") val juz: Int?
)
