package com.faxel.music.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlaylistAdd
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.faxel.music.R
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Song
import com.faxel.music.playback.PlayerConnection

fun formatTime(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val seconds = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%d:%02d".format(minutes, seconds)
}

/** Pochette (de l'album) ou, à défaut, un dégradé avec une note. */
@Composable
fun Artwork(song: Song?, size: Dp, shape: Shape = RoundedCornerShape(8.dp), modifier: Modifier = Modifier) {
    val colors = paletteFor(song?.albumId ?: 0L)
    Box(
        modifier
            .size(size)
            .clip(shape)
            .background(Brush.linearGradient(colors)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Rounded.MusicNote, null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(size * 0.4f))
        if (song != null) {
            AsyncImage(
                model = song.artUri,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun SongRow(
    song: Song,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    number: Int? = null,
    extraMenu: (@Composable (close: () -> Unit) -> Unit)? = null,
) {
    val playing = PlayerConnection.currentId == song.id
    Row(
        modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (number != null) {
            Text("$number", color = Color.Gray, fontSize = 14.sp, modifier = Modifier.width(26.dp))
        } else {
            Artwork(song, 48.dp)
            Spacer(Modifier.width(12.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(
                song.title,
                color = if (playing) MaterialTheme.colorScheme.primary else Color.White,
                fontWeight = if (playing) FontWeight.Bold else FontWeight.Medium,
                fontSize = 16.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val sub = listOf(song.displayArtist, formatTime(song.duration)).filter { it.isNotBlank() }.joinToString(" · ")
            Text(sub, color = Color.Gray, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (MusicRepository.isFavorite(song)) {
            Icon(Icons.Rounded.Favorite, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
        }
        SongMenuButton(song, extraMenu)
    }
}

@Composable
fun SongMenuButton(song: Song, extraMenu: (@Composable (close: () -> Unit) -> Unit)? = null, tint: Color = Color.Gray) {
    var open by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    val context = LocalContext.current
    Box {
        IconButton(onClick = { open = true }) {
            Icon(Icons.Rounded.MoreVert, null, tint = tint)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.play_next)) },
                leadingIcon = { Icon(Icons.Rounded.SkipNext, null) },
                onClick = { PlayerConnection.playNext(song); open = false },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.add_to_queue)) },
                leadingIcon = { Icon(Icons.Rounded.QueueMusic, null) },
                onClick = { PlayerConnection.addToQueue(listOf(song)); open = false },
            )
            DropdownMenuItem(
                text = { Text(stringResource(if (MusicRepository.isFavorite(song)) R.string.remove_favorite else R.string.favorite)) },
                leadingIcon = {
                    Icon(if (MusicRepository.isFavorite(song)) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null)
                },
                onClick = { MusicRepository.toggleFavorite(song); open = false },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.add_to_playlist)) },
                leadingIcon = { Icon(Icons.Rounded.PlaylistAdd, null) },
                onClick = { picking = true; open = false },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.share)) },
                leadingIcon = { Icon(Icons.Rounded.Share, null) },
                onClick = {
                    open = false
                    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                        type = "audio/*"
                        putExtra(android.content.Intent.EXTRA_STREAM, song.uri)
                        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    context.startActivity(android.content.Intent.createChooser(intent, song.title))
                },
            )
            extraMenu?.invoke { open = false }
        }
    }
    if (picking) {
        PlaylistPicker(songs = listOf(song), onDismiss = { picking = false })
    }
}

/** Choisir une playlist (ou en créer une) pour y ajouter des morceaux. */
@Composable
fun PlaylistPicker(songs: List<Song>, onDismiss: () -> Unit) {
    var creating by remember { mutableStateOf(false) }
    if (creating) {
        NameDialog(
            title = stringResource(R.string.new_playlist),
            initial = "",
            onDismiss = onDismiss,
            onConfirm = { name ->
                val list = MusicRepository.createPlaylist(name)
                MusicRepository.addToPlaylist(list.id, songs)
                onDismiss()
            },
        )
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.add_to_playlist)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "+ " + stringResource(R.string.new_playlist),
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.fillMaxWidth().clickable { creating = true }.padding(vertical = 10.dp),
                )
                MusicRepository.playlists.forEach { list ->
                    Text(
                        list.name,
                        modifier = Modifier.fillMaxWidth().clickable {
                            MusicRepository.addToPlaylist(list.id, songs)
                            onDismiss()
                        }.padding(vertical = 10.dp),
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
fun NameDialog(title: String, initial: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            androidx.compose.material3.OutlinedTextField(value = text, onValueChange = { text = it }, singleLine = true)
        },
        confirmButton = { TextButton(onClick = { onConfirm(text) }) { Text(stringResource(R.string.ok)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
fun EmptyState(title: String, subtitle: String = "", modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Rounded.MusicNote, null, tint = Color.Gray, modifier = Modifier.size(48.dp))
        Spacer(Modifier.size(12.dp))
        Text(title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        if (subtitle.isNotBlank()) {
            Spacer(Modifier.size(6.dp))
            Text(subtitle, color = Color.Gray, fontSize = 14.sp)
        }
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        color = Color.White,
        fontWeight = FontWeight.Bold,
        fontSize = 22.sp,
        modifier = modifier.padding(horizontal = 16.dp, vertical = 10.dp),
    )
}
