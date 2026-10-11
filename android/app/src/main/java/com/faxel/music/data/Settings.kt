package com.faxel.music.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf

/** Un réglage gardé dans le téléphone, observé par l'interface. */
class StringPref(private val key: String, default: String) {
    private val state = mutableStateOf(default)
    var value: String
        get() = state.value
        set(v) {
            state.value = v
            Settings.prefs.edit().putString(key, v).apply()
        }

    fun load(p: SharedPreferences) {
        state.value = p.getString(key, state.value) ?: state.value
    }
}

class BoolPref(private val key: String, default: Boolean) {
    private val state = mutableStateOf(default)
    var value: Boolean
        get() = state.value
        set(v) {
            state.value = v
            Settings.prefs.edit().putBoolean(key, v).apply()
        }

    fun load(p: SharedPreferences) {
        state.value = p.getBoolean(key, state.value)
    }
}

class FloatPref(private val key: String, default: Float) {
    private val state = mutableStateOf(default)
    var value: Float
        get() = state.value
        set(v) {
            state.value = v
            Settings.prefs.edit().putFloat(key, v).apply()
        }

    fun load(p: SharedPreferences) {
        state.value = p.getFloat(key, state.value)
    }
}

/** Personnalisation : profil, couleur, pochette, fond, visualiseur, paroles. */
object Settings {
    lateinit var prefs: SharedPreferences

    val userName = StringPref("userName", "")
    val accent = StringPref("accent", "FF2D60")
    val coverStyle = StringPref("coverStyle", "square")
    val background = StringPref("background", "aurora")
    val visualizer = StringPref("visualizer", "bars")
    val animations = BoolPref("animations", true)
    val lyricsAuto = BoolPref("lyricsAuto", true)
    val lyricsSize = FloatPref("lyricsSize", 26f)
    val sortSongs = StringPref("sortSongs", "date")

    val accents = listOf("FF2D60", "FF9500", "FFCC00", "34C759", "00C7BE", "0A84FF", "5E5CE6", "BF5AF2", "FF375F", "A2845E")

    fun init(context: Context) {
        prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        listOf(userName, accent, coverStyle, background, visualizer, sortSongs).forEach { it.load(prefs) }
        listOf(animations, lyricsAuto).forEach { it.load(prefs) }
        lyricsSize.load(prefs)
    }
}
