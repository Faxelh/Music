package com.faxel.music.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.faxel.music.data.Settings

fun colorFromHex(hex: String): Color {
    val clean = hex.trim().removePrefix("#")
    val value = clean.toLongOrNull(16) ?: 0xFF2D60L
    return Color(0xFF000000 or value)
}

val accent: Color get() = colorFromHex(Settings.accent.value)

/** Palettes des pochettes de secours (selon le morceau). */
val artworkPalettes = listOf(
    listOf(Color(0xFFFF2D60), Color(0xFFFF9500)),
    listOf(Color(0xFF5E5CE6), Color(0xFFBF5AF2)),
    listOf(Color(0xFF0A84FF), Color(0xFF00C7BE)),
    listOf(Color(0xFF34C759), Color(0xFF30B0C7)),
    listOf(Color(0xFFFF9F0A), Color(0xFFFF375F)),
    listOf(Color(0xFFAF52DE), Color(0xFFFF2D55)),
    listOf(Color(0xFF64D2FF), Color(0xFF5E5CE6)),
)

fun paletteFor(seed: Long): List<Color> = artworkPalettes[((seed % artworkPalettes.size + artworkPalettes.size) % artworkPalettes.size).toInt()]

@Composable
fun MusicTheme(content: @Composable () -> Unit) {
    val main = accent
    val scheme = darkColorScheme(
        primary = main,
        secondary = main,
        tertiary = main,
        background = Color.Black,
        surface = Color(0xFF111114),
        surfaceVariant = Color(0xFF1C1C21),
        surfaceContainer = Color(0xFF16161A),
        surfaceContainerHigh = Color(0xFF1E1E24),
        onBackground = Color.White,
        onSurface = Color.White,
        onPrimary = Color.White,
    )
    MaterialTheme(colorScheme = scheme, content = content)
}
