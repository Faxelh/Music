package com.faxel.music.ui

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.os.LocaleListCompat
import com.faxel.music.R
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Settings

val coverStyles = listOf(
    "square" to R.string.cover_square,
    "round" to R.string.cover_round,
    "vinyl" to R.string.cover_vinyl,
    "cd" to R.string.cover_cd,
    "floating" to R.string.cover_floating,
)

val backgroundStyles = listOf(
    "artwork" to R.string.bg_artwork,
    "aurora" to R.string.bg_aurora,
    "rainbow" to R.string.bg_rainbow,
    "black" to R.string.bg_black,
)

val visualizerStyles = listOf(
    "bars" to R.string.vis_bars,
    "mirror" to R.string.vis_mirror,
    "wave" to R.string.vis_wave,
    "dots" to R.string.vis_dots,
    "none" to R.string.vis_none,
)

private val languages = listOf(
    "" to R.string.lang_system,
    "fr" to R.string.lang_fr,
    "en" to R.string.lang_en,
    "es" to R.string.lang_es,
    "de" to R.string.lang_de,
    "ru" to R.string.lang_ru,
)

@Composable
fun SettingsScreen() {
    var naming by remember { mutableStateOf(false) }
    var eqOpen by remember { mutableStateOf(false) }
    val currentLang = AppCompatDelegate.getApplicationLocales().toLanguageTags().substringBefore('-')

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
        item {
            Text(
                stringResource(R.string.tab_settings), color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }

        item { Group(stringResource(R.string.profile)) }
        item {
            SettingRow(stringResource(R.string.your_name), Settings.userName.value.ifBlank { "—" }) { naming = true }
        }
        item {
            ChoiceRow(stringResource(R.string.language), languages, currentLang) { tag ->
                AppCompatDelegate.setApplicationLocales(
                    if (tag.isEmpty()) LocaleListCompat.getEmptyLocaleList() else LocaleListCompat.forLanguageTags(tag),
                )
            }
        }

        item { Group(stringResource(R.string.appearance)) }
        item {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text(stringResource(R.string.accent_color), color = Color.White, fontSize = 16.sp)
                Spacer(Modifier.size(10.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(Settings.accents) { hex ->
                        val selected = Settings.accent.value.equals(hex, true)
                        Box(
                            Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(colorFromHex(hex))
                                .border(if (selected) 3.dp else 0.dp, Color.White, CircleShape)
                                .clickable { Settings.accent.value = hex },
                        )
                    }
                }
            }
        }
        item { ChoiceRow(stringResource(R.string.cover_style), coverStyles, Settings.coverStyle.value) { Settings.coverStyle.value = it } }
        item { ChoiceRow(stringResource(R.string.background), backgroundStyles, Settings.background.value) { Settings.background.value = it } }
        item { ChoiceRow(stringResource(R.string.visualizer), visualizerStyles, Settings.visualizer.value) { Settings.visualizer.value = it } }
        item { SwitchRow(stringResource(R.string.animations), Settings.animations.value) { Settings.animations.value = it } }

        item { Group(stringResource(R.string.playback)) }
        item { SettingRow(stringResource(R.string.equalizer), "") { eqOpen = true } }
        item { SwitchRow(stringResource(R.string.lyrics_auto), Settings.lyricsAuto.value) { Settings.lyricsAuto.value = it } }
        item {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
                Text(stringResource(R.string.lyrics_size) + " : ${Settings.lyricsSize.value.toInt()}", color = Color.White, fontSize = 16.sp)
                Slider(Settings.lyricsSize.value, { Settings.lyricsSize.value = it }, valueRange = 18f..40f)
            }
        }

        item { Group(stringResource(R.string.library_group)) }
        item {
            SettingRow(stringResource(R.string.rescan), stringResource(R.string.songs_found, MusicRepository.songs.size)) {
                MusicRepository.refresh()
            }
        }
        item { Group(stringResource(R.string.upd_section)) }
        item { com.faxel.music.update.UpdateSettingsRow() }
        item {
            Text(
                "Music " + com.faxel.music.update.Updater.currentVersion, color = Color.Gray, fontSize = 13.sp,
                modifier = Modifier.fillMaxWidth().padding(24.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }

    if (naming) {
        NameDialog(stringResource(R.string.your_name), Settings.userName.value, onDismiss = { naming = false }) {
            Settings.userName.value = it.trim(); naming = false
        }
    }
    if (eqOpen) EqualizerSheet(onDismiss = { eqOpen = false })
}

@Composable
private fun Group(title: String) {
    Text(
        title.uppercase(), color = MaterialTheme.colorScheme.primary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = 16.dp, top = 22.dp, bottom = 4.dp),
    )
}

@Composable
private fun SettingRow(title: String, value: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = Color.White, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Text(value, color = Color.Gray, fontSize = 15.sp)
        Spacer(Modifier.width(6.dp))
        Text("›", color = Color.Gray, fontSize = 20.sp)
    }
}

@Composable
private fun SwitchRow(title: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onChange(!value) }.padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = Color.White, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Switch(value, onChange)
    }
}

@Composable
fun ChoiceRow(title: String, options: List<Pair<String, Int>>, selected: String, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val label = options.firstOrNull { it.first == selected }?.second ?: options.first().second
    Box {
        SettingRow(title, stringResource(label)) { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }, modifier = Modifier.clip(RoundedCornerShape(12.dp))) {
            options.forEach { (key, text) ->
                DropdownMenuItem(
                    text = { Text((if (key == selected) "✓ " else "") + stringResource(text)) },
                    onClick = { onSelect(key); open = false },
                )
            }
        }
    }
}
