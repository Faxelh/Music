package com.faxel.music.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccessTime
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Help
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Radio
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.faxel.music.R
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Song
import com.faxel.music.playback.PlayerConnection
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Une sélection automatique de la bibliothèque. */
private class SmartMix(val id: String, val title: Int, val icon: ImageVector, val colors: List<Color>, val songs: List<Song>)

/** Mélange stable sur la journée (les mêmes choix toute la journée, d'autres demain). */
private fun <T> List<T>.daily(salt: String): List<T> {
    val seed = (MusicRepository.dayKey(System.currentTimeMillis()) + salt).hashCode().toLong()
    return shuffled(java.util.Random(seed))
}

/**
 * Onglet « Découvrir » (à la place de la recherche, qui s'ouvre depuis sa barre) :
 * mix automatiques, radios, artiste du jour, statistiques d'écoute, dossiers.
 */
@Composable
fun DiscoverScreen(nav: Navigator) {
    val songs = MusicRepository.songs
    val counts = MusicRepository.playCounts
    val favorites = MusicRepository.favorites
    val recent = MusicRepository.recent
    val mixes = remember(songs, counts, favorites, recent) {
        val now = System.currentTimeMillis() / 1000
        val month = 30L * 24 * 3600
        val recentSet = recent.toSet()
        listOf(
            SmartMix("fav", R.string.mix_favorites, Icons.Rounded.Favorite, listOf(Color(0xFFFF3366), Color(0xFFBF1A80)),
                songs.filter { it.id in favorites }),
            SmartMix("loop", R.string.mix_loop, Icons.Rounded.LocalFireDepartment, listOf(Color(0xFFFF7319), Color(0xFFE62633)),
                MusicRepository.mostPlayed),
            SmartMix("new", R.string.mix_new, Icons.Rounded.AutoAwesome, listOf(Color(0xFF3399FF), Color(0xFF664DF2)),
                songs.filter { now - it.dateAdded < month }),
            SmartMix("again", R.string.mix_rediscover, Icons.Rounded.History, listOf(Color(0xFF26B38C), Color(0xFF1A6699)),
                songs.filter { (counts[it.id] ?: 0) > 0 && it.id !in recentSet }.daily("again")),
            SmartMix("never", R.string.mix_never, Icons.Rounded.Help, listOf(Color(0xFF8C59F2), Color(0xFF403399)),
                songs.filter { (counts[it.id] ?: 0) == 0 }.daily("never")),
            SmartMix("short", R.string.mix_short, Icons.Rounded.Bolt, listOf(Color(0xFFF2BF1A), Color(0xFFF2731A)),
                songs.filter { it.duration in 1 until 180_000 }),
            SmartMix("long", R.string.mix_long, Icons.Rounded.AccessTime, listOf(Color(0xFF4D5980), Color(0xFF26334D)),
                songs.filter { it.duration > 360_000 }),
        ).filter { it.songs.size >= if (it.id == "fav") 2 else 3 }
    }
    val radios = remember(songs, counts, favorites) {
        (MusicRepository.mostPlayed.take(4) + songs.filter { it.id in favorites }.daily("fav").take(4) + songs.daily("radio").take(8))
            .distinctBy { it.id }.take(8)
    }
    val artist = remember(MusicRepository.artists) { MusicRepository.artists.filter { it.songs.size >= 2 }.daily("artist").firstOrNull() }
    val album = remember(MusicRepository.albums) { MusicRepository.albums.filter { it.songs.size >= 2 }.daily("album").firstOrNull() }
    val folders = remember(songs) {
        songs.groupBy { it.folder }.filter { it.key.isNotBlank() && it.value.size >= 3 }.entries
            .sortedByDescending { it.value.size }.take(12).map { it.key to it.value }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Row(Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.for_you).uppercase(), color = Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Text(stringResource(R.string.tab_discover), color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                }
                Box(
                    Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary)
                        .clickable(enabled = songs.isNotEmpty()) { PlayerConnection.play(songs, shuffled = true) },
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Rounded.Shuffle, null, tint = Color.White) }
            }
        }
        item {
            Row(
                Modifier.padding(horizontal = 16.dp).fillMaxWidth().height(44.dp).clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF1C1C21)).clickable { nav.open(Route.Search) }.padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.Search, null, tint = Color.Gray)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.search_hint), color = Color.Gray, fontSize = 15.sp)
            }
        }
        if (songs.isEmpty()) {
            item { EmptyState(stringResource(R.string.discover_empty)) }
            return@LazyColumn
        }
        if (mixes.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.your_mixes), Modifier.padding(top = 10.dp)) }
            mixes.chunked(2).forEach { pair ->
                item(key = "mix-" + pair.first().id) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        pair.forEach { mix -> MixTile(mix, Modifier.weight(1f)) }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
        if (radios.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.radios), Modifier.padding(top = 10.dp)) }
            item {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(radios, key = { "r-${it.id}" }) { song -> RadioTile(song) }
                }
            }
        }
        artist?.let { a ->
            item { SectionTitle(stringResource(R.string.artist_of_day), Modifier.padding(top = 10.dp)) }
            item {
                Row(
                    Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp))
                        .background(Brush.linearGradient(listOf(Color(0xFF6A3DE8), Color(0xFF2A1A66)))).padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Artwork(a.songs.first(), 84.dp, CircleShape)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(a.name, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(pluralStringResource(R.plurals.songs_count, a.songs.size, a.songs.size), color = Color.White.copy(alpha = 0.8f), fontSize = 13.sp)
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Pill(stringResource(R.string.listen), Color.White, Color.Black) { PlayerConnection.play(a.songs, shuffled = true) }
                            Pill(stringResource(R.string.view), Color.White.copy(alpha = 0.2f), Color.White) { nav.open(Route.ArtistDetail(a.name)) }
                        }
                    }
                }
            }
        }
        item { StatsCard() }
        album?.let { al ->
            item { SectionTitle(stringResource(R.string.album_of_day), Modifier.padding(top = 10.dp)) }
            item {
                Row(Modifier.padding(horizontal = 16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.clickable { nav.open(Route.AlbumDetail(al.id)) }) {
                        Artwork(al.songs.first(), 96.dp, RoundedCornerShape(12.dp))
                    }
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(al.title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(al.artist, color = Color.Gray, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            pluralStringResource(R.plurals.songs_count, al.songs.size, al.songs.size) + " · " + formatTime(al.songs.sumOf { it.duration }),
                            color = Color.Gray, fontSize = 13.sp,
                        )
                        Spacer(Modifier.height(6.dp))
                        Pill(stringResource(R.string.play_all), MaterialTheme.colorScheme.primary, Color.White) { PlayerConnection.play(al.songs) }
                    }
                }
            }
        }
        if (folders.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.by_folder), Modifier.padding(top = 10.dp)) }
            item {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(folders, key = { "f-${it.first}" }) { (name, list) ->
                        Column(
                            Modifier.clip(RoundedCornerShape(16.dp))
                                .background(Brush.linearGradient(folderColors(name)))
                                .clickable { PlayerConnection.play(list, shuffled = true) }
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                        ) {
                            Icon(Icons.Rounded.Folder, null, tint = Color.White, modifier = Modifier.size(18.dp))
                            Text(name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(pluralStringResource(R.plurals.songs_count, list.size, list.size), color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

private val palettes = listOf(
    listOf(Color(0xFFFF2E61), Color(0xFFFF8C33)),
    listOf(Color(0xFF5959F2), Color(0xFF9E40D9)),
    listOf(Color(0xFF1AB3A6), Color(0xFF2659B3)),
    listOf(Color(0xFFF25999), Color(0xFFFAA659)),
    listOf(Color(0xFF4DBF66), Color(0xFF1A7366)),
)

private fun folderColors(name: String) = palettes[(name.hashCode() and 0x7fffffff) % palettes.size]

@Composable
private fun MixTile(mix: SmartMix, modifier: Modifier) {
    var menu by remember { mutableStateOf(false) }
    val title = stringResource(mix.title)
    Box(modifier) {
        Box(
            Modifier.fillMaxWidth().height(112.dp).clip(RoundedCornerShape(18.dp))
                .background(Brush.linearGradient(mix.colors))
                .clickable { PlayerConnection.play(mix.songs, shuffled = mix.id != "loop" && mix.id != "new") },
        ) {
            Icon(
                mix.icon, null, tint = Color.White.copy(alpha = 0.18f),
                modifier = Modifier.align(Alignment.TopEnd).size(64.dp).padding(top = 4.dp, end = 4.dp),
            )
            Column(Modifier.fillMaxHeight().padding(12.dp), verticalArrangement = Arrangement.SpaceBetween) {
                Icon(mix.icon, null, tint = Color.White, modifier = Modifier.size(20.dp))
                Column {
                    Text(title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(pluralStringResource(R.plurals.songs_count, mix.songs.size, mix.songs.size), color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
                }
            }
            Box(Modifier.align(Alignment.BottomEnd).size(40.dp).clickable { menu = true }, contentAlignment = Alignment.Center) {
                Text("•••", color = Color.White.copy(alpha = 0.8f), fontSize = 12.sp)
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.play_all)) }, leadingIcon = { Icon(Icons.Rounded.PlayArrow, null) },
                onClick = { menu = false; PlayerConnection.play(mix.songs) })
            DropdownMenuItem(text = { Text(stringResource(R.string.shuffle)) }, leadingIcon = { Icon(Icons.Rounded.Shuffle, null) },
                onClick = { menu = false; PlayerConnection.play(mix.songs, shuffled = true) })
            DropdownMenuItem(text = { Text(stringResource(R.string.add_to_queue)) },
                onClick = { menu = false; PlayerConnection.addToQueue(mix.songs) })
            HorizontalDivider()
            DropdownMenuItem(text = { Text(stringResource(R.string.save_playlist)) },
                onClick = { menu = false; MusicRepository.createPlaylist(title, mix.songs.map { it.id }) })
        }
    }
}

@Composable
private fun RadioTile(song: Song) {
    Column(Modifier.width(140.dp).clickable { PlayerConnection.playRadio(song) }) {
        Box(Modifier.size(140.dp).clip(RoundedCornerShape(14.dp))) {
            Artwork(song, 140.dp, RoundedCornerShape(0.dp))
            Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f)))))
            Row(Modifier.align(Alignment.BottomStart).padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Radio, null, tint = Color.White, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.radio_label), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(song.title, color = Color.White, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(song.displayArtist, color = Color.Gray, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Pill(text: String, background: Color, foreground: Color, onClick: () -> Unit) {
    Text(
        text, color = foreground, fontWeight = FontWeight.Bold, fontSize = 14.sp,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(background).clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 7.dp),
    )
}

@Composable
private fun StatsCard() {
    val week = MusicRepository.listeningMinutes(7)
    val weekMinutes = week.sumOf { it.second }
    val peak = maxOf(1.0, week.maxOf { it.second })
    val streak = MusicRepository.listeningStreak
    val counts = MusicRepository.playCounts
    val total = counts.values.sum()
    val top = MusicRepository.mostPlayed.firstOrNull()
    val topArtist = remember(counts) {
        val per = HashMap<String, Int>()
        counts.forEach { (id, n) -> MusicRepository.song(id)?.takeIf { it.hasArtist }?.let { per[it.artist] = (per[it.artist] ?: 0) + n } }
        per.maxByOrNull { it.value }?.key
    }
    val primary = MaterialTheme.colorScheme.primary
    val dayFormat = remember { SimpleDateFormat("EEEEE", Locale.getDefault()) }
    Column {
    SectionTitle(stringResource(R.string.your_listening), Modifier.padding(top = 10.dp))
    Column(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color(0xFF1C1C21)).padding(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Stat(formatMinutes(weekMinutes), stringResource(R.string.this_week))
            Stat("$total", stringResource(R.string.plays))
            Stat("$streak", stringResource(R.string.streak_days))
        }
        Spacer(Modifier.height(14.dp))
        Row(Modifier.fillMaxWidth().height(92.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            week.forEachIndexed { index, (day, minutes) ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.fillMaxWidth().height((4 + minutes / peak * 66).dp).clip(RoundedCornerShape(5.dp))
                            .background(if (index == week.size - 1) primary else primary.copy(alpha = 0.45f)),
                    )
                    Spacer(Modifier.height(5.dp))
                    Text(dayFormat.format(Date(day)), color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        if (topArtist != null || top != null) {
            HorizontalDivider(Modifier.padding(vertical = 10.dp), color = Color.White.copy(alpha = 0.1f))
            topArtist?.let {
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
                    Text(stringResource(R.string.top_artist), color = Color.Gray, fontSize = 14.sp, modifier = Modifier.weight(1f))
                    Text(it, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            top?.let { song ->
                Row(Modifier.fillMaxWidth().clickable { PlayerConnection.play(MusicRepository.mostPlayed) }.padding(vertical = 3.dp)) {
                    Text(stringResource(R.string.top_song), color = Color.Gray, fontSize = 14.sp, modifier = Modifier.weight(1f))
                    Text(song.title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    Text("  ×${counts[song.id] ?: 0}", color = primary, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }
        } else if (weekMinutes < 1) {
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.stats_empty), color = Color.Gray, fontSize = 13.sp)
        }
    }
    }
}

@Composable
private fun Stat(value: String, label: String) {
    Column {
        Text(value, color = MaterialTheme.colorScheme.primary, fontSize = 24.sp, fontWeight = FontWeight.Black)
        Text(label, color = Color.Gray, fontSize = 12.sp)
    }
}

private fun formatMinutes(minutes: Double): String {
    val total = Math.round(minutes).toInt()
    return if (total < 60) "$total min" else "${total / 60} h ${"%02d".format(total % 60)}"
}
