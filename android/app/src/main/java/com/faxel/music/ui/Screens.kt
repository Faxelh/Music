@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)

package com.faxel.music.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.Sort
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
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
import com.faxel.music.data.Album
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Settings
import com.faxel.music.data.Song
import com.faxel.music.playback.PlayerConnection
import java.util.Calendar

// MARK: Accueil

@Composable
fun HomeScreen(nav: Navigator, onOpenPlayer: () -> Unit) {
    val songs = MusicRepository.songs
    val hour = remember { Calendar.getInstance().get(Calendar.HOUR_OF_DAY) }
    val greeting = stringResource(
        when (hour) {
            in 5..11 -> R.string.good_morning
            in 12..17 -> R.string.good_afternoon
            else -> R.string.good_evening
        },
    )
    val name = Settings.userName.value
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Row(Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (name.isBlank()) greeting else "$greeting, $name", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                    Text(pluralStringResource(R.plurals.songs_count, songs.size, songs.size), color = Color.Gray, fontSize = 15.sp)
                }
                IconButton(
                    onClick = { nav.open(Route.Search) },
                    modifier = Modifier.size(44.dp).clip(CircleShape).background(Color(0xFF1C1C21)),
                ) { Icon(Icons.Rounded.Search, null, tint = Color.White) }
            }
        }
        if (songs.isEmpty()) {
            item {
                EmptyState(
                    stringResource(if (MusicRepository.loaded) R.string.no_music else R.string.loading),
                    if (MusicRepository.loaded) stringResource(R.string.no_music_hint) else "",
                )
            }
            return@LazyColumn
        }
        item {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                BigButton(stringResource(R.string.play_all), Icons.Rounded.PlayArrow, Modifier.weight(1f)) {
                    PlayerConnection.play(songs); onOpenPlayer()
                }
                BigButton(stringResource(R.string.shuffle), Icons.Rounded.Shuffle, Modifier.weight(1f)) {
                    PlayerConnection.play(songs, shuffled = true); onOpenPlayer()
                }
            }
        }
        item {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ShortcutCard(stringResource(R.string.favorites), Icons.Rounded.Favorite, listOf(Color(0xFFFF2D60), Color(0xFFFF6B8B)), Modifier.weight(1f)) {
                    nav.open(Route.Favorites)
                }
                ShortcutCard(stringResource(R.string.recent), Icons.Rounded.History, listOf(Color(0xFF5E5CE6), Color(0xFFBF5AF2)), Modifier.weight(1f)) {
                    nav.open(Route.Recent)
                }
                ShortcutCard(stringResource(R.string.most_played), Icons.Rounded.TrendingUp, listOf(Color(0xFFFF9500), Color(0xFFFFCC00)), Modifier.weight(1f)) {
                    nav.open(Route.MostPlayed)
                }
            }
        }
        val recent = MusicRepository.recentSongs.take(12)
        if (recent.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.recent)) }
            item { SongCarousel(recent) }
        }
        val albums = MusicRepository.albums.sortedByDescending { album -> album.songs.maxOf { it.dateAdded } }.take(12)
        if (albums.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.recent_albums)) }
            item {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(albums, key = { it.id }) { album -> AlbumCard(album, 140) { nav.open(Route.AlbumDetail(album.id)) } }
                }
            }
        }
        item { SectionTitle(stringResource(R.string.recently_added)) }
        items(songs.take(20), key = { "added-${it.id}" }) { song ->
            SongRow(song, onClick = { PlayerConnection.play(songs, songs.indexOf(song)) })
        }
    }
}

@Composable
private fun BigButton(text: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = modifier.height(50.dp),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1C1C21), contentColor = MaterialTheme.colorScheme.primary),
    ) {
        Icon(icon, null)
        Spacer(Modifier.width(6.dp))
        Text(text, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ShortcutCard(title: String, icon: ImageVector, colors: List<Color>, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Brush.linearGradient(colors))
            .clickable(onClick = onClick)
            .padding(12.dp)
            .height(64.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Icon(icon, null, tint = Color.White)
        Text(title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun SongCarousel(songs: List<Song>) {
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        itemsIndexed(songs, key = { _, s -> "c-${s.id}" }) { index, song ->
            Column(Modifier.width(130.dp).clickable { PlayerConnection.play(songs, index) }) {
                Artwork(song, 130.dp, RoundedCornerShape(12.dp))
                Spacer(Modifier.height(6.dp))
                Text(song.title, color = Color.White, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(song.displayArtist, color = Color.Gray, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
fun AlbumCard(album: Album, size: Int, onClick: () -> Unit) {
    Column(Modifier.width(size.dp).clickable(onClick = onClick)) {
        Artwork(album.songs.first(), size.dp, RoundedCornerShape(12.dp))
        Spacer(Modifier.height(6.dp))
        Text(album.title, color = Color.White, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(album.artist, color = Color.Gray, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// MARK: Bibliothèque

@Composable
fun LibraryScreen(nav: Navigator) {
    var creating by remember { mutableStateOf(false) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Text(
                stringResource(R.string.tab_library), color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }
        item { LibraryLink(Icons.Rounded.MusicNote, stringResource(R.string.songs), MusicRepository.songs.size) { nav.open(Route.Songs) } }
        item { LibraryLink(Icons.Rounded.Album, stringResource(R.string.albums), MusicRepository.albums.size) { nav.open(Route.Albums) } }
        item { LibraryLink(Icons.Rounded.Person, stringResource(R.string.artists), MusicRepository.artists.size) { nav.open(Route.Artists) } }
        item { LibraryLink(Icons.AutoMirrored.Rounded.QueueMusic, stringResource(R.string.playlists), MusicRepository.playlists.size) { nav.open(Route.Playlists) } }
        item { LibraryLink(Icons.Rounded.Folder, stringResource(R.string.folders), null) { nav.open(Route.Folders) } }
        item { LibraryLink(Icons.Rounded.Favorite, stringResource(R.string.favorites), MusicRepository.favorites.size) { nav.open(Route.Favorites) } }
        item {
            Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                SectionTitle(stringResource(R.string.playlists), Modifier.weight(1f))
                Text(
                    "+ " + stringResource(R.string.new_playlist), color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable { creating = true }.padding(8.dp),
                )
            }
        }
        items(MusicRepository.playlists, key = { it.id }) { list ->
            val first = MusicRepository.playlistSongs(list).firstOrNull()
            Row(
                Modifier.fillMaxWidth().clickable { nav.open(Route.PlaylistDetail(list.id)) }.padding(horizontal = 16.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Artwork(first, 52.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(list.name, color = Color.White, fontSize = 16.sp)
                    Text(pluralStringResource(R.plurals.songs_count, list.songIds.size, list.songIds.size), color = Color.Gray, fontSize = 13.sp)
                }
            }
        }
    }
    if (creating) {
        NameDialog(stringResource(R.string.new_playlist), "", onDismiss = { creating = false }) {
            MusicRepository.createPlaylist(it); creating = false
        }
    }
}

@Composable
private fun LibraryLink(icon: ImageVector, title: String, count: Int?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(26.dp))
        Spacer(Modifier.width(16.dp))
        Text(title, color = Color.White, fontSize = 18.sp, modifier = Modifier.weight(1f))
        if (count != null) Text("$count", color = Color.Gray, fontSize = 15.sp)
        Text("  ›", color = Color.Gray, fontSize = 20.sp)
    }
    HorizontalDivider(Modifier.padding(start = 58.dp), color = Color.White.copy(alpha = 0.06f))
}

// MARK: Pages intérieures

@Composable
private fun GoBack(nav: Navigator) {
    androidx.compose.runtime.LaunchedEffect(Unit) { nav.back() }
}

@Composable
private fun PageHeader(title: String, nav: Navigator, actions: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().statusBarsPadding().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { nav.back() }) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = MaterialTheme.colorScheme.primary)
        }
        Text(title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        actions()
    }
}

@Composable
fun RouteScreen(route: Route, nav: Navigator) {
    when (route) {
        Route.Songs -> AllSongsPage(nav)
        Route.Albums -> AlbumsPage(nav)
        Route.Artists -> ArtistsPage(nav)
        Route.Playlists -> PlaylistsPage(nav)
        Route.Folders -> FoldersPage(nav)
        Route.Favorites -> SongListPage(stringResource(R.string.favorites), MusicRepository.favoriteSongs, nav)
        Route.Recent -> SongListPage(stringResource(R.string.recent), MusicRepository.recentSongs, nav)
        Route.MostPlayed -> SongListPage(stringResource(R.string.most_played), MusicRepository.mostPlayed, nav)
        Route.Search -> SearchScreen(nav)
        is Route.AlbumDetail -> {
            val album = MusicRepository.albums.firstOrNull { it.id == route.id }
            if (album == null) GoBack(nav) else CollectionPage(album.title, album.artist, album.songs, nav, numbered = true)
        }
        is Route.ArtistDetail -> {
            val artist = MusicRepository.artists.firstOrNull { it.name == route.name }
            if (artist == null) GoBack(nav) else ArtistPage(artist.name, artist.songs, nav)
        }
        is Route.FolderDetail -> {
            val songs = MusicRepository.songs.filter { it.folder == route.name }
            CollectionPage(route.name, "", songs, nav)
        }
        is Route.PlaylistDetail -> PlaylistPage(route.id, nav)
    }
}

@Composable
private fun PlayShuffleRow(songs: List<Song>) {
    if (songs.isEmpty()) return
    Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        BigButton(stringResource(R.string.play_all), Icons.Rounded.PlayArrow, Modifier.weight(1f)) { PlayerConnection.play(songs) }
        BigButton(stringResource(R.string.shuffle), Icons.Rounded.Shuffle, Modifier.weight(1f)) { PlayerConnection.play(songs, shuffled = true) }
    }
}

@Composable
private fun AllSongsPage(nav: Navigator) {
    var sortOpen by remember { mutableStateOf(false) }
    val sort = Settings.sortSongs.value
    val songs = remember(MusicRepository.songs, sort) {
        val all = MusicRepository.songs
        when (sort) {
            "title" -> all.sortedBy { it.title.lowercase() }
            "artist" -> all.sortedBy { it.displayArtist.lowercase() }
            "duration" -> all.sortedByDescending { it.duration }
            else -> all
        }
    }
    SongSelectionHost(songs) {
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            PageHeader(stringResource(R.string.songs), nav) {
                SelectToggle()
                Box {
                    IconButton(onClick = { sortOpen = true }) { Icon(Icons.Rounded.Sort, null, tint = MaterialTheme.colorScheme.primary) }
                    DropdownMenu(sortOpen, onDismissRequest = { sortOpen = false }) {
                        listOf("date" to R.string.sort_date, "title" to R.string.sort_title, "artist" to R.string.sort_artist, "duration" to R.string.sort_duration)
                            .forEach { (key, label) ->
                                DropdownMenuItem(
                                    text = { Text((if (sort == key) "✓ " else "") + stringResource(label)) },
                                    onClick = { Settings.sortSongs.value = key; sortOpen = false },
                                )
                            }
                    }
                }
            }
        }
        item { PlayShuffleRow(songs) }
        itemsIndexed(songs, key = { _, s -> s.id }) { index, song ->
            SongRow(song, onClick = { PlayerConnection.play(songs, index) }, selectable = true)
        }
        item { SelectionSpacer() }
    }
    }
}

@Composable
private fun SongListPage(title: String, songs: List<Song>, nav: Navigator) {
    SongSelectionHost(songs) {
    LazyColumn(Modifier.fillMaxSize()) {
        item { PageHeader(title, nav) { if (songs.isNotEmpty()) SelectToggle() } }
        if (songs.isEmpty()) item { EmptyState(stringResource(R.string.nothing_here)) }
        item { PlayShuffleRow(songs) }
        itemsIndexed(songs, key = { _, s -> s.id }) { index, song ->
            SongRow(song, onClick = { PlayerConnection.play(songs, index) }, selectable = true)
        }
        item { SelectionSpacer() }
    }
    }
}

/** Bouton « Sélectionner » / fermer la sélection. */
@Composable
private fun SelectToggle() {
    val selection = SongSelection.state
    IconButton(onClick = { if (selection.active) selection.finish() else selection.start() }) {
        Icon(
            if (selection.active) Icons.Rounded.Close else Icons.Rounded.Checklist, null,
            tint = MaterialTheme.colorScheme.primary,
        )
    }
}

/** Place pour la barre de sélection en bas de la liste. */
@Composable
private fun SelectionSpacer() {
    if (SongSelection.state.active) Spacer(Modifier.height(150.dp))
}

@Composable
private fun CollectionPage(title: String, subtitle: String, songs: List<Song>, nav: Navigator, numbered: Boolean = false) {
    SongSelectionHost(songs) {
    LazyColumn(Modifier.fillMaxSize()) {
        item { PageHeader("", nav) { SelectToggle() } }
        item {
            Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Artwork(songs.firstOrNull(), 220.dp, RoundedCornerShape(16.dp))
                Spacer(Modifier.height(12.dp))
                Text(title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                if (subtitle.isNotBlank()) Text(subtitle, color = MaterialTheme.colorScheme.primary, fontSize = 16.sp)
                val minutes = songs.sumOf { it.duration } / 60000
                Text(pluralStringResource(R.plurals.songs_count, songs.size, songs.size) + " · $minutes min", color = Color.Gray, fontSize = 13.sp)
            }
        }
        item { PlayShuffleRow(songs) }
        itemsIndexed(songs, key = { _, s -> s.id }) { index, song ->
            SongRow(song, onClick = { PlayerConnection.play(songs, index) }, number = if (numbered) index + 1 else null, selectable = true)
        }
        item { SelectionSpacer() }
    }
    }
}

@Composable
private fun ArtistPage(name: String, songs: List<Song>, nav: Navigator) {
    val albums = MusicRepository.albums.filter { album -> album.songs.any { it.artist == name } }
    SongSelectionHost(songs) {
    LazyColumn(Modifier.fillMaxSize()) {
        item { PageHeader(name, nav) { SelectToggle() } }
        item { PlayShuffleRow(songs) }
        if (albums.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.albums)) }
            item {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(albums, key = { it.id }) { album -> AlbumCard(album, 130) { nav.open(Route.AlbumDetail(album.id)) } }
                }
            }
        }
        item { SectionTitle(stringResource(R.string.songs)) }
        itemsIndexed(songs, key = { _, s -> s.id }) { index, song ->
            SongRow(song, onClick = { PlayerConnection.play(songs, index) }, selectable = true)
        }
        item { SelectionSpacer() }
    }
    }
}

@Composable
private fun AlbumsPage(nav: Navigator) {
    val albums = MusicRepository.albums
    LazyVerticalGrid(
        GridCells.Adaptive(150.dp), Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) { PageHeader(stringResource(R.string.albums), nav) }
        items(albums, key = { it.id }) { album ->
            Column(Modifier.clickable { nav.open(Route.AlbumDetail(album.id)) }) {
                Artwork(album.songs.first(), 170.dp, RoundedCornerShape(12.dp), Modifier.fillMaxWidth())
                Spacer(Modifier.height(6.dp))
                Text(album.title, color = Color.White, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(album.artist, color = Color.Gray, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun ArtistsPage(nav: Navigator) {
    LazyColumn(Modifier.fillMaxSize()) {
        item { PageHeader(stringResource(R.string.artists), nav) }
        items(MusicRepository.artists, key = { it.name }) { artist ->
            Row(
                Modifier.fillMaxWidth().clickable { nav.open(Route.ArtistDetail(artist.name)) }.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Artwork(artist.songs.first(), 52.dp, CircleShape)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(artist.name, color = Color.White, fontSize = 16.sp)
                    Text(pluralStringResource(R.plurals.songs_count, artist.songs.size, artist.songs.size), color = Color.Gray, fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
private fun FoldersPage(nav: Navigator) {
    val folders = MusicRepository.songs.groupBy { it.folder }.toList().sortedBy { it.first.lowercase() }
    LazyColumn(Modifier.fillMaxSize()) {
        item { PageHeader(stringResource(R.string.folders), nav) }
        items(folders, key = { it.first }) { (name, songs) ->
            Row(
                Modifier.fillMaxWidth().clickable { nav.open(Route.FolderDetail(name)) }.padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.Folder, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(34.dp))
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(name.ifBlank { "/" }, color = Color.White, fontSize = 16.sp)
                    Text(pluralStringResource(R.plurals.songs_count, songs.size, songs.size), color = Color.Gray, fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
private fun PlaylistsPage(nav: Navigator) {
    var creating by remember { mutableStateOf(false) }
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            PageHeader(stringResource(R.string.playlists), nav) {
                Text("+", color = MaterialTheme.colorScheme.primary, fontSize = 28.sp, modifier = Modifier.clickable { creating = true }.padding(horizontal = 16.dp))
            }
        }
        if (MusicRepository.playlists.isEmpty()) item { EmptyState(stringResource(R.string.no_playlists)) }
        items(MusicRepository.playlists, key = { it.id }) { list ->
            Row(
                Modifier.fillMaxWidth().clickable { nav.open(Route.PlaylistDetail(list.id)) }.padding(horizontal = 16.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Artwork(MusicRepository.playlistSongs(list).firstOrNull(), 52.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(list.name, color = Color.White, fontSize = 16.sp)
                    Text(pluralStringResource(R.plurals.songs_count, list.songIds.size, list.songIds.size), color = Color.Gray, fontSize = 13.sp)
                }
            }
        }
    }
    if (creating) {
        NameDialog(stringResource(R.string.new_playlist), "", onDismiss = { creating = false }) {
            MusicRepository.createPlaylist(it); creating = false
        }
    }
}

@Composable
private fun PlaylistPage(id: String, nav: Navigator) {
    val list = MusicRepository.playlists.firstOrNull { it.id == id }
    if (list == null) {
        GoBack(nav); return
    }
    val songs = MusicRepository.playlistSongs(list)
    var renaming by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            PageHeader(list.name, nav) {
                IconButton(onClick = { renaming = true }) { Icon(Icons.Rounded.Edit, null, tint = MaterialTheme.colorScheme.primary) }
                IconButton(onClick = { MusicRepository.deletePlaylist(id) }) { Icon(Icons.Rounded.Delete, null, tint = MaterialTheme.colorScheme.primary) }
            }
        }
        item { PlayShuffleRow(songs) }
        item {
            Text(
                "+ " + stringResource(R.string.add_songs), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.fillMaxWidth().clickable { adding = true }.padding(16.dp),
            )
        }
        if (songs.isEmpty()) item { EmptyState(stringResource(R.string.nothing_here)) }
        itemsIndexed(songs, key = { _, s -> s.id }) { index, song ->
            SongRow(song, onClick = { PlayerConnection.play(songs, index) }, extraMenu = { close ->
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.remove_from_playlist)) },
                    leadingIcon = { Icon(Icons.Rounded.Close, null) },
                    onClick = { MusicRepository.removeFromPlaylist(id, song); close() },
                )
            })
        }
    }
    if (renaming) {
        NameDialog(stringResource(R.string.rename), list.name, onDismiss = { renaming = false }) {
            MusicRepository.renamePlaylist(id, it); renaming = false
        }
    }
    if (adding) {
        SongPickerDialog(exclude = list.songIds.toSet(), onDismiss = { adding = false }) { picked ->
            MusicRepository.addToPlaylist(id, picked); adding = false
        }
    }
}

@Composable
private fun SongPickerDialog(exclude: Set<Long>, onDismiss: () -> Unit, onDone: (List<Song>) -> Unit) {
    var query by remember { mutableStateOf("") }
    var picked by remember { mutableStateOf<List<Song>>(emptyList()) }
    val candidates = MusicRepository.songs.filter { it.id !in exclude }.filter {
        query.isBlank() || it.title.contains(query, true) || it.artist.contains(query, true)
    }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.add_songs)) },
        text = {
            Column {
                OutlinedTextField(query, { query = it }, singleLine = true, placeholder = { Text(stringResource(R.string.search_hint)) }, modifier = Modifier.fillMaxWidth())
                LazyColumn(Modifier.height(360.dp)) {
                    items(candidates, key = { it.id }) { song ->
                        val selected = song in picked
                        Row(
                            Modifier.fillMaxWidth().clickable { picked = if (selected) picked - song else picked + song }.padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Artwork(song, 40.dp)
                            Spacer(Modifier.width(10.dp))
                            Text(song.title, color = if (selected) MaterialTheme.colorScheme.primary else Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            if (selected) Text("✓", color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        },
        confirmButton = { androidx.compose.material3.TextButton(onClick = { onDone(picked) }) { Text(stringResource(R.string.ok) + " (${picked.size})") } },
        dismissButton = { androidx.compose.material3.TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

// MARK: Recherche

@Composable
fun SearchScreen(nav: Navigator) {
    var query by rememberSaveable { mutableStateOf("") }
    val q = query.trim()
    val songs = if (q.isEmpty()) emptyList() else MusicRepository.songs.filter {
        it.title.contains(q, true) || it.artist.contains(q, true) || it.album.contains(q, true)
    }
    val albums = if (q.isEmpty()) emptyList() else MusicRepository.albums.filter { it.title.contains(q, true) }
    val artists = if (q.isEmpty()) emptyList() else MusicRepository.artists.filter { it.name.contains(q, true) }
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Column(Modifier.statusBarsPadding().padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { nav.back() }) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, tint = MaterialTheme.colorScheme.primary)
                    }
                    Text(stringResource(R.string.tab_search), color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = query, onValueChange = { query = it }, singleLine = true,
                    placeholder = { Text(stringResource(R.string.search_hint)) },
                    leadingIcon = { Icon(Icons.Rounded.Search, null) },
                    trailingIcon = {
                        if (query.isNotEmpty()) IconButton(onClick = { query = "" }) { Icon(Icons.Rounded.Close, null) }
                    },
                    shape = RoundedCornerShape(14.dp),
                    colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Color(0xFF1C1C21), focusedContainerColor = Color(0xFF1C1C21)),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        if (q.isNotEmpty() && songs.isEmpty() && albums.isEmpty() && artists.isEmpty()) {
            item { EmptyState(stringResource(R.string.no_results)) }
        }
        if (artists.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.artists)) }
            items(artists.take(5), key = { "a-${it.name}" }) { artist ->
                Row(
                    Modifier.fillMaxWidth().clickable { nav.open(Route.ArtistDetail(artist.name)) }.padding(horizontal = 16.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Artwork(artist.songs.first(), 48.dp, CircleShape)
                    Spacer(Modifier.width(12.dp))
                    Text(artist.name, color = Color.White, fontSize = 16.sp)
                }
            }
        }
        if (albums.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.albums)) }
            item {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(albums, key = { it.id }) { album -> AlbumCard(album, 120) { nav.open(Route.AlbumDetail(album.id)) } }
                }
            }
        }
        if (songs.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.songs)) }
            itemsIndexed(songs, key = { _, s -> "s-${s.id}" }) { index, song ->
                SongRow(song, onClick = { PlayerConnection.play(songs, index) })
            }
        }
    }
}
