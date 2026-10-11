package com.faxel.music.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.faxel.music.R
import com.faxel.music.data.MusicRepository
import com.faxel.music.playback.PlayerConnection
import kotlinx.coroutines.delay

/** Pages qu'on peut ouvrir à l'intérieur d'un onglet. */
sealed class Route {
    data object Songs : Route()
    data object Albums : Route()
    data object Artists : Route()
    data object Playlists : Route()
    data object Folders : Route()
    data object Favorites : Route()
    data object Recent : Route()
    data object MostPlayed : Route()
    data class AlbumDetail(val id: Long) : Route()
    data class ArtistDetail(val name: String) : Route()
    data class PlaylistDetail(val id: String) : Route()
    data class FolderDetail(val name: String) : Route()
}

enum class Tab(val icon: ImageVector, val label: Int) {
    Home(Icons.Rounded.Home, R.string.tab_home),
    Library(Icons.Rounded.LibraryMusic, R.string.tab_library),
    Search(Icons.Rounded.Search, R.string.tab_search),
    Settings(Icons.Rounded.Settings, R.string.tab_settings),
}

/** Navigation simple : une pile de pages par onglet. */
class Navigator {
    var tab by mutableStateOf(Tab.Home)
    private val stacks = Tab.entries.associateWith { mutableStateListOf<Route>() }

    val stack: List<Route> get() = stacks.getValue(tab)
    val top: Route? get() = stack.lastOrNull()

    fun open(route: Route) {
        stacks.getValue(tab).add(route)
    }

    fun back(): Boolean {
        val list = stacks.getValue(tab)
        if (list.isEmpty()) return false
        list.removeAt(list.size - 1)
        return true
    }

    fun select(new: Tab) {
        if (new == tab) stacks.getValue(tab).clear() else tab = new
    }
}

/** Position de lecture rafraîchie régulièrement (pour la barre et les paroles). */
@Composable
fun rememberPosition(): Pair<Long, Long> {
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }
    val controller = PlayerConnection.controller
    val playing = PlayerConnection.isPlaying
    val id = PlayerConnection.currentId
    LaunchedEffect(controller, playing, id) {
        while (true) {
            val c = controller ?: break
            position = c.currentPosition.coerceAtLeast(0)
            duration = c.duration.takeIf { it > 0 } ?: (PlayerConnection.current?.duration ?: 0L)
            if (!playing) break
            delay(200)
        }
    }
    return position to duration
}

@Composable
fun MusicRoot(granted: Boolean, onAskPermission: () -> Unit) {
    val nav = remember { Navigator() }
    var playerOpen by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(MusicRepository.loaded, PlayerConnection.controller) {
        if (MusicRepository.loaded) PlayerConnection.restoreIfEmpty()
    }

    BackHandler(enabled = playerOpen || nav.top != null) {
        if (playerOpen) playerOpen = false else nav.back()
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Scaffold(
            containerColor = Color.Black,
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            bottomBar = {
                Column(Modifier.background(Color(0xF20D0D10))) {
                    if (PlayerConnection.current != null) {
                        MiniPlayer(onOpen = { playerOpen = true })
                    }
                    NavigationBar(containerColor = Color.Transparent, tonalElevation = 0.dp) {
                        Tab.entries.forEach { tab ->
                            NavigationBarItem(
                                selected = nav.tab == tab,
                                onClick = { nav.select(tab) },
                                icon = { Icon(tab.icon, null) },
                                label = { Text(stringResource(tab.label), fontSize = 11.sp) },
                                colors = NavigationBarItemDefaults.colors(
                                    selectedIconColor = MaterialTheme.colorScheme.primary,
                                    selectedTextColor = MaterialTheme.colorScheme.primary,
                                    indicatorColor = Color.Transparent,
                                    unselectedIconColor = Color.Gray,
                                    unselectedTextColor = Color.Gray,
                                ),
                            )
                        }
                    }
                }
            },
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(padding)) {
                if (!granted) {
                    PermissionGate(onAskPermission)
                } else {
                    val top = nav.top
                    if (top != null) {
                        RouteScreen(top, nav)
                    } else {
                        when (nav.tab) {
                            Tab.Home -> HomeScreen(nav, onOpenPlayer = { playerOpen = true })
                            Tab.Library -> LibraryScreen(nav)
                            Tab.Search -> SearchScreen(nav)
                            Tab.Settings -> SettingsScreen()
                        }
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = playerOpen && PlayerConnection.current != null,
            enter = slideInVertically(tween(320)) { it },
            exit = slideOutVertically(tween(260)) { it },
        ) {
            PlayerScreen(onClose = { playerOpen = false })
        }
    }
    com.faxel.music.update.UpdateCheck()
}

@Composable
private fun PermissionGate(onAsk: () -> Unit) {
    Column(
        Modifier.fillMaxSize().statusBarsPadding().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        Artwork(null, 96.dp, RoundedCornerShape(24.dp))
        Spacer(Modifier.height(20.dp))
        Text(stringResource(R.string.permission_title), color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(stringResource(R.string.permission_text), color = Color.Gray, fontSize = 15.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.height(20.dp))
        Button(onClick = onAsk) { Text(stringResource(R.string.permission_button)) }
    }
}

@Composable
private fun MiniPlayer(onOpen: () -> Unit) {
    val song = PlayerConnection.current ?: return
    val (position, duration) = rememberPosition()
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF1C1C21))
            .clickable(onClick = onOpen),
    ) {
        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Artwork(song, 44.dp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(song.title, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (song.displayArtist.isNotBlank()) {
                    Text(song.displayArtist, color = Color.Gray, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            IconButton(onClick = { PlayerConnection.toggle() }) {
                Icon(if (PlayerConnection.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.White, modifier = Modifier.size(32.dp))
            }
            IconButton(onClick = { PlayerConnection.next() }) {
                Icon(Icons.Rounded.SkipNext, null, tint = Color.White, modifier = Modifier.size(28.dp))
            }
        }
        LinearProgressIndicator(
            progress = { if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f },
            modifier = Modifier.fillMaxWidth().height(2.dp),
            color = MaterialTheme.colorScheme.primary,
            trackColor = Color.White.copy(alpha = 0.1f),
        )
    }
}
