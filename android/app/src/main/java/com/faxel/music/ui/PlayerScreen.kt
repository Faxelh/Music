package com.faxel.music.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Equalizer
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Subtitles
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.media3.common.Player
import coil.compose.AsyncImage
import com.faxel.music.R
import com.faxel.music.data.LyricsStore
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Settings
import com.faxel.music.data.Song
import com.faxel.music.playback.AudioFx
import com.faxel.music.playback.PlayerConnection
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

@Composable
fun PlayerScreen(onClose: () -> Unit) {
    val song = PlayerConnection.current ?: return
    var showLyrics by remember { mutableStateOf(false) }
    var showQueue by remember { mutableStateOf(false) }
    var showEq by remember { mutableStateOf(false) }
    var showSleep by remember { mutableStateOf(false) }
    var showSpeed by remember { mutableStateOf(false) }
    var showLyricsSearch by remember { mutableStateOf(false) }
    var showInfo by remember { mutableStateOf(false) }
    val (position, duration) = rememberPosition()

    LaunchedEffect(song.id) { LyricsStore.load(song, Settings.lyricsAuto.value) }
    LiveSpectrum()

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) { detectTapGestures { } },
    ) {
        PlayerBackground(song)
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            val boxW = maxWidth
            val boxH = maxHeight
            val compact = boxH < 680.dp
            Column(Modifier.fillMaxSize().padding(horizontal = 22.dp)) {
                PlayerHeader(
                    song, onClose,
                    onLyricsSearch = { showLyricsSearch = true },
                    onTuning = { showSpeed = true },
                    onInfo = { showInfo = true },
                )
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    if (showLyrics) {
                        LiveLyrics(position)
                    } else {
                        val side = minOf(boxW - 44.dp, boxH * (if (compact) 0.36f else 0.42f))
                        SwipeCover(song, side)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(song.title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(song.displayArtist.ifBlank { song.album }, color = Color.White.copy(alpha = 0.65f), fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    val fav = MusicRepository.isFavorite(song)
                    IconButton(onClick = { MusicRepository.toggleFavorite(song) }) {
                        Icon(if (fav) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null,
                            tint = if (fav) MaterialTheme.colorScheme.primary else Color.White, modifier = Modifier.size(28.dp))
                    }
                }
                if (Settings.visualizer.value != "none") {
                    Spacer(Modifier.height(8.dp))
                    VisualizerView(Modifier.fillMaxWidth().height(if (compact) 34.dp else 48.dp))
                }
                LoopBadges(onTuning = { showSpeed = true })
                Scrubber(position, duration)
                Transport()
                ToolsRow(
                    lyricsOn = showLyrics,
                    onLyrics = { showLyrics = !showLyrics },
                    onQueue = { showQueue = true },
                    onEq = { showEq = true },
                    onSleep = { showSleep = true },
                    onSpeed = { showSpeed = true },
                )
                Spacer(Modifier.height(8.dp))
            }
        }
    }

    if (showQueue) QueueSheet(onDismiss = { showQueue = false })
    if (showEq) EqualizerSheet(onDismiss = { showEq = false })
    if (showSleep) SleepSheet(onDismiss = { showSleep = false })
    if (showSpeed) SpeedSheet(onDismiss = { showSpeed = false })
    if (showInfo) InfoSheet(song, onDismiss = { showInfo = false })
    if (showLyricsSearch) LyricsSearchSheet(song, onDismiss = { showLyricsSearch = false })
}

// MARK: Spectre réel (demande le micro une fois)

@Composable
private fun LiveSpectrum() {
    val context = LocalContext.current
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    val wanted = Settings.visualizer.value != "none" || Settings.background.value == "aurora"
    LaunchedEffect(wanted) {
        val prefs = context.getSharedPreferences("settings", 0)
        if (wanted && !granted && !prefs.getBoolean("askedMic", false)) {
            prefs.edit().putBoolean("askedMic", true).apply()
            launcher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    DisposableEffect(granted, wanted, PlayerConnection.currentId) {
        if (granted && wanted) AudioFx.startVisualizer()
        onDispose { AudioFx.stopVisualizer() }
    }
}

/** Niveaux 0…1 : spectre réel si dispo, sinon une animation qui suit la lecture. */
@Composable
fun rememberLevels(count: Int): FloatArray {
    val live = AudioFx.spectrumLive
    val spectrum = AudioFx.spectrum
    var fake by remember { mutableStateOf(FloatArray(count)) }
    val playing = PlayerConnection.isPlaying
    LaunchedEffect(live, playing, count) {
        if (live) return@LaunchedEffect
        var t = 0.0
        while (true) {
            t += 0.12
            fake = FloatArray(count) { i ->
                if (!playing) 0.05f else {
                    val base = 0.35 + 0.3 * sin(t * 1.7 + i * 0.55) + 0.25 * sin(t * 3.1 + i * 1.3)
                    (base * (1.0 - i.toDouble() / (count * 1.6))).toFloat().coerceIn(0.05f, 1f)
                }
            }
            if (!playing) break
            delay(70)
        }
    }
    if (!live) return fake
    return FloatArray(count) { i -> spectrum[(i * spectrum.size / count).coerceIn(0, spectrum.size - 1)] }
}

// MARK: Fond

@Composable
private fun PlayerBackground(song: Song) {
    val style = Settings.background.value
    val colors = paletteFor(song.albumId)
    val animate = Settings.animations.value
    when (style) {
        "black" -> Box(Modifier.fillMaxSize().background(Color.Black))
        "artwork" -> Box(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(colors[0].copy(alpha = 0.7f), Color.Black))))
            if (Build.VERSION.SDK_INT >= 31) {
                AsyncImage(
                    model = song.artUri, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().scale(1.4f).blur(60.dp),
                )
            }
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)))
        }
        else -> {
            val transition = rememberInfiniteTransition(label = "bg")
            val phase by transition.animateFloat(
                0f, 1f, infiniteRepeatable(tween(14000, easing = LinearEasing), RepeatMode.Restart), label = "phase",
            )
            val p = if (animate) phase else 0.2f
            val levels = rememberLevels(8)
            val bass = (levels.take(3).average().toFloat()).coerceIn(0f, 1f)
            val pulse by animateFloatAsState(bass, tween(120), label = "pulse")
            val palette = if (style == "rainbow") {
                listOf(Color(0xFFFF2D55), Color(0xFFFF9500), Color(0xFFFFCC00), Color(0xFF34C759), Color(0xFF0A84FF), Color(0xFFBF5AF2))
            } else {
                listOf(colors[0], colors[1], accent)
            }
            Canvas(Modifier.fillMaxSize()) {
                drawRect(Color.Black)
                palette.forEachIndexed { i, color ->
                    val angle = 2 * PI * (p + i.toFloat() / palette.size)
                    val cx = size.width * (0.5f + 0.35f * sin(angle).toFloat())
                    val cy = size.height * (0.4f + 0.3f * sin(angle * 0.7 + i).toFloat())
                    val radius = size.maxDimension * (0.45f + 0.15f * pulse)
                    drawCircle(
                        Brush.radialGradient(listOf(color.copy(alpha = 0.55f), Color.Transparent), Offset(cx, cy), radius),
                        radius, Offset(cx, cy),
                    )
                }
                drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f))))
            }
        }
    }
}

// MARK: En-tête

@Composable
private fun PlayerHeader(song: Song, onClose: () -> Unit, onLyricsSearch: () -> Unit, onTuning: () -> Unit, onInfo: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        CircleButton(Icons.Rounded.KeyboardArrowDown, onClose)
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            val count = PlayerConnection.queueIds.size
            Text(
                stringResource(R.string.index_of, PlayerConnection.index + 1, count),
                color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
            )
            Text(song.album, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box {
            CircleButton(Icons.Rounded.MoreVert) { menu = true }
            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.radio_song)) }, onClick = { menu = false; PlayerConnection.playRadio(song) })
                DropdownMenuItem(
                    text = {
                        Text(
                            stringResource(
                                when {
                                    PlayerConnection.loopA == null -> R.string.loop_set_a
                                    PlayerConnection.loopB == null -> R.string.loop_set_b
                                    else -> R.string.loop_stop
                                },
                            ),
                        )
                    },
                    onClick = { menu = false; PlayerConnection.cycleLoop() },
                )
                DropdownMenuItem(text = { Text(stringResource(R.string.speed_pitch)) }, onClick = { menu = false; onTuning() })
                DropdownMenuItem(text = { Text(stringResource(R.string.info)) }, onClick = { menu = false; onInfo() })
                HorizontalDivider()
                MenuGroup(stringResource(R.string.cover_style), coverStyles, Settings.coverStyle.value) { Settings.coverStyle.value = it }
                HorizontalDivider()
                MenuGroup(stringResource(R.string.background), backgroundStyles, Settings.background.value) { Settings.background.value = it }
                HorizontalDivider()
                MenuGroup(stringResource(R.string.visualizer), visualizerStyles, Settings.visualizer.value) { Settings.visualizer.value = it }
                HorizontalDivider()
                DropdownMenuItem(text = { Text(stringResource(R.string.search_lyrics)) }, onClick = { menu = false; onLyricsSearch() })
                DropdownMenuItem(text = { Text(stringResource(R.string.add_to_queue)) }, onClick = { menu = false; PlayerConnection.playNext(song) })
            }
        }
    }
}

@Composable
private fun MenuGroup(title: String, options: List<Pair<String, Int>>, selected: String, onSelect: (String) -> Unit) {
    Text(title, color = Color.Gray, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
    options.forEach { (key, label) ->
        DropdownMenuItem(
            text = { Text((if (key == selected) "✓  " else "     ") + stringResource(label)) },
            onClick = { onSelect(key) },
        )
    }
}

@Composable
private fun CircleButton(icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(
        Modifier.size(38.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Color.White) }
}

// MARK: Pochette

@Composable
private fun SwipeCover(song: Song, side: Dp) {
    var drag by remember { mutableFloatStateOf(0f) }
    var burst by remember { mutableStateOf(0) }
    val offset by animateFloatAsState(drag, label = "drag")
    Box(
        Modifier
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (drag < -120) PlayerConnection.next() else if (drag > 120) PlayerConnection.previous()
                        drag = 0f
                    },
                    onDragCancel = { drag = 0f },
                ) { _, amount -> drag += amount }
            }
            // Double-toucher la pochette : ajoute aux favoris avec un grand cœur.
            .pointerInput(song.id) {
                detectTapGestures(onDoubleTap = {
                    if (!MusicRepository.isFavorite(song)) MusicRepository.toggleFavorite(song)
                    burst++
                })
            }
            .padding(start = (offset.coerceAtLeast(0f) / 3).dp, end = (-offset.coerceAtMost(0f) / 3).dp),
        contentAlignment = Alignment.Center,
    ) {
        CoverView(song, side)
        HeartBurst(burst)
    }
}

@Composable
private fun HeartBurst(trigger: Int) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        shown = true
        delay(650)
        shown = false
    }
    val scale by animateFloatAsState(if (shown) 1f else 0.2f, androidx.compose.animation.core.spring(0.45f, 400f), label = "heart")
    val alpha by animateFloatAsState(if (shown) 1f else 0f, tween(if (shown) 120 else 300), label = "heartAlpha")
    if (alpha > 0.01f) {
        Icon(
            Icons.Rounded.Favorite, null, tint = Color.White.copy(alpha = alpha),
            modifier = Modifier.size(110.dp).scale(scale),
        )
    }
}

/** Boucle A–B et tonalité en cours (touchez pour changer). */
@Composable
private fun LoopBadges(onTuning: () -> Unit) {
    val a = PlayerConnection.loopA
    val b = PlayerConnection.loopB
    val steps = PlayerConnection.semitones
    if (a == null && steps == 0) return
    val primary = MaterialTheme.colorScheme.primary
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
        if (a != null) {
            Text(
                "A ${formatTime(a)}  →  B " + (b?.let { formatTime(it) } ?: "?"),
                color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(primary.copy(alpha = 0.85f))
                    .clickable { PlayerConnection.cycleLoop() }.padding(horizontal = 10.dp, vertical = 5.dp),
            )
            Box(
                Modifier.size(26.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.18f)).clickable { PlayerConnection.clearLoop() },
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Rounded.Close, null, tint = Color.White, modifier = Modifier.size(14.dp)) }
        }
        if (steps != 0) {
            Text(
                stringResource(R.string.pitch) + " " + (if (steps > 0) "+$steps" else "$steps"),
                color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.18f))
                    .clickable(onClick = onTuning).padding(horizontal = 10.dp, vertical = 5.dp),
            )
        }
    }
}

@Composable
private fun CoverView(song: Song, side: Dp) {
    val playing = PlayerConnection.isPlaying
    val animate = Settings.animations.value
    val transition = rememberInfiniteTransition(label = "spin")
    val spin by transition.animateFloat(0f, 360f, infiniteRepeatable(tween(12000, easing = LinearEasing)), label = "angle")
    var frozen by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(playing) { if (!playing) frozen = spin }
    val angle = if (playing && animate) spin else frozen
    val scale by animateFloatAsState(if (playing) 1f else 0.86f, tween(400), label = "scale")
    val levels = rememberLevels(6)
    val bass = levels.take(2).average().toFloat()

    when (Settings.coverStyle.value) {
        "round" -> Artwork(song, side, CircleShape, Modifier.scale(scale).shadow(24.dp, CircleShape))
        "vinyl" -> Box(Modifier.size(side).scale(scale), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize().rotate(angle)) {
                drawCircle(Color(0xFF111111))
                for (i in 1..14) drawCircle(Color.White.copy(alpha = 0.05f), size.minDimension / 2 * (0.42f + i * 0.04f), style = Stroke(1f))
            }
            Artwork(song, side * 0.42f, CircleShape, Modifier.rotate(angle))
            Box(Modifier.size(10.dp).clip(CircleShape).background(Color.Black))
        }
        "cd" -> Box(Modifier.size(side).scale(scale), contentAlignment = Alignment.Center) {
            Artwork(song, side, CircleShape, Modifier.rotate(angle))
            Canvas(Modifier.fillMaxSize().rotate(angle)) {
                drawCircle(
                    Brush.sweepGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.25f), Color.Transparent, Color.Cyan.copy(alpha = 0.15f), Color.Transparent)),
                )
                drawCircle(Color.Black, size.minDimension * 0.08f)
                drawCircle(Color.White.copy(alpha = 0.4f), size.minDimension * 0.16f, style = Stroke(2f))
            }
        }
        "floating" -> {
            val float by transition.animateFloat(-8f, 8f, infiniteRepeatable(tween(2600), RepeatMode.Reverse), label = "float")
            Artwork(
                song, side, RoundedCornerShape(22.dp),
                Modifier.padding(top = (if (animate) float + 8 else 8f).dp).scale(scale * (1f + bass * 0.04f)).shadow(30.dp, RoundedCornerShape(22.dp)),
            )
        }
        else -> Artwork(song, side, RoundedCornerShape(18.dp), Modifier.scale(scale).shadow(24.dp, RoundedCornerShape(18.dp)))
    }
}

// MARK: Visualiseur

@Composable
fun VisualizerView(modifier: Modifier) {
    val style = Settings.visualizer.value
    val count = if (style == "dots") 24 else 36
    val levels = rememberLevels(count)
    val color = MaterialTheme.colorScheme.primary
    Canvas(modifier) {
        val w = size.width / count
        when (style) {
            "mirror" -> levels.forEachIndexed { i, v ->
                val h = size.height * (0.06f + v * 0.94f)
                drawRoundRect(color.copy(alpha = 0.9f), Offset(i * w + w * 0.2f, (size.height - h) / 2), Size(w * 0.6f, h), CornerRadius(w))
            }
            "wave" -> {
                val path = Path()
                levels.forEachIndexed { i, v ->
                    val x = i * w + w / 2
                    val y = size.height / 2 + (if (i % 2 == 0) -1 else 1) * v * size.height / 2
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                drawPath(path, color, style = Stroke(4f))
            }
            "dots" -> levels.forEachIndexed { i, v ->
                val dots = 5
                for (d in 0 until dots) {
                    val on = v * dots > d
                    drawCircle(
                        if (on) color else Color.White.copy(alpha = 0.1f), w * 0.28f,
                        Offset(i * w + w / 2, size.height - (d + 0.5f) * size.height / dots),
                    )
                }
            }
            else -> levels.forEachIndexed { i, v ->
                val h = size.height * (0.06f + v * 0.94f)
                drawRoundRect(
                    Brush.verticalGradient(listOf(color, color.copy(alpha = 0.4f)), size.height - h, size.height),
                    Offset(i * w + w * 0.18f, size.height - h), Size(w * 0.64f, h), CornerRadius(w / 3),
                )
            }
        }
    }
}

// MARK: Barre de progression et commandes

@Composable
private fun Scrubber(position: Long, duration: Long) {
    var dragging by remember { mutableStateOf<Float?>(null) }
    val fraction = dragging ?: if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
    Column {
        Slider(
            value = fraction,
            onValueChange = { dragging = it },
            onValueChangeFinished = {
                dragging?.let { PlayerConnection.seek((it * duration).toLong()) }
                dragging = null
            },
            colors = SliderDefaults.colors(
                thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.2f),
            ),
        )
        Row(Modifier.fillMaxWidth()) {
            val shown = if (dragging != null) (fraction * duration).toLong() else position
            Text(formatTime(shown), color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp, modifier = Modifier.weight(1f))
            Text("-" + formatTime((duration - shown).coerceAtLeast(0)), color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
        }
    }
}

@Composable
private fun Transport() {
    val primary = MaterialTheme.colorScheme.primary
    Row(
        Modifier.fillMaxWidth().padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = { PlayerConnection.toggleShuffle() }) {
            Icon(Icons.Rounded.Shuffle, null, tint = if (PlayerConnection.shuffle) primary else Color.White.copy(alpha = 0.7f))
        }
        IconButton(onClick = { PlayerConnection.previous() }, modifier = Modifier.size(56.dp)) {
            Icon(Icons.Rounded.SkipPrevious, null, tint = Color.White, modifier = Modifier.size(44.dp))
        }
        Box(
            Modifier.size(76.dp).clip(CircleShape).background(Color.White).clickable { PlayerConnection.toggle() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(if (PlayerConnection.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.Black, modifier = Modifier.size(44.dp))
        }
        IconButton(onClick = { PlayerConnection.next() }, modifier = Modifier.size(56.dp)) {
            Icon(Icons.Rounded.SkipNext, null, tint = Color.White, modifier = Modifier.size(44.dp))
        }
        IconButton(onClick = { PlayerConnection.cycleRepeat() }) {
            Icon(
                if (PlayerConnection.repeatMode == Player.REPEAT_MODE_ONE) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat, null,
                tint = if (PlayerConnection.repeatMode != Player.REPEAT_MODE_OFF) primary else Color.White.copy(alpha = 0.7f),
            )
        }
    }
}

@Composable
private fun ToolsRow(lyricsOn: Boolean, onLyrics: () -> Unit, onQueue: () -> Unit, onEq: () -> Unit, onSleep: () -> Unit, onSpeed: () -> Unit) {
    val primary = MaterialTheme.colorScheme.primary
    val dim = Color.White.copy(alpha = 0.7f)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        IconButton(onClick = onLyrics) { Icon(Icons.Rounded.Subtitles, null, tint = if (lyricsOn) primary else dim) }
        IconButton(onClick = onQueue) { Icon(Icons.AutoMirrored.Rounded.QueueMusic, null, tint = dim) }
        IconButton(onClick = onEq) { Icon(Icons.Rounded.Equalizer, null, tint = if (AudioFx.enabled) primary else dim) }
        IconButton(onClick = onSleep) {
            Icon(Icons.Rounded.Timer, null, tint = if (PlayerConnection.sleepEnd != null || PlayerConnection.sleepAtEnd) primary else dim)
        }
        IconButton(onClick = onSpeed) {
            if (PlayerConnection.speed != 1f) {
                Text("${PlayerConnection.speed}×", color = primary, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            } else {
                Icon(Icons.Rounded.Speed, null, tint = if (PlayerConnection.semitones != 0) primary else dim)
            }
        }
    }
}

// MARK: Paroles

@Composable
private fun LiveLyrics(position: Long) {
    val lyrics = LyricsStore.lyrics
    if (lyrics == null) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                stringResource(if (LyricsStore.loading || LyricsStore.searching) R.string.lyrics_searching else R.string.no_lyrics),
                color = Color.White.copy(alpha = 0.7f), fontSize = 18.sp, textAlign = TextAlign.Center,
            )
            if (!LyricsStore.loading && !LyricsStore.searching) {
                Spacer(Modifier.height(12.dp))
                PlayerConnection.current?.let { song ->
                    Button(onClick = { LyricsStore.fetchBest(song) }) { Text(stringResource(R.string.search_lyrics)) }
                }
            }
        }
        return
    }
    val current = lyrics.currentIndex(position / 1000.0)
    val state = rememberLazyListState()
    LaunchedEffect(current) {
        if (current != null) state.animateScrollToItem((current - 2).coerceAtLeast(0))
    }
    val size = Settings.lyricsSize.value
    LazyColumn(state = state, modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        itemsIndexed(lyrics.lines, key = { _, l -> l.id }) { index, line ->
            val active = !lyrics.isSynced || index == current
            Text(
                line.text.ifBlank { "♪" },
                color = if (active) Color.White else Color.White.copy(alpha = 0.35f),
                fontSize = (if (lyrics.isSynced) size else size * 0.75f).sp,
                fontWeight = FontWeight.Bold,
                lineHeight = (size * 1.25f).sp,
                modifier = Modifier.fillMaxWidth().clickable(enabled = line.time != null) {
                    line.time?.let { PlayerConnection.seek((it * 1000).toLong()) }
                },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LyricsSearchSheet(song: Song, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf(LyricsStore.guess(song).let { (t, a) -> listOfNotNull(a, t).joinToString(" ") }) }
    LaunchedEffect(Unit) { LyricsStore.search(song, query) }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color(0xFF16161A)) {
        Column(Modifier.padding(horizontal = 16.dp).height(520.dp)) {
            Text(stringResource(R.string.search_lyrics), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(query, { query = it }, singleLine = true, modifier = Modifier.weight(1f))
                TextButton(onClick = { LyricsStore.search(song, query) }) { Text(stringResource(R.string.tab_search)) }
            }
            if (LyricsStore.lyrics != null) {
                TextButton(onClick = { LyricsStore.delete(song); onDismiss() }) { Text(stringResource(R.string.remove_lyrics)) }
            }
            if (LyricsStore.searching) Text(stringResource(R.string.lyrics_searching), color = Color.Gray, modifier = Modifier.padding(12.dp))
            else if (LyricsStore.searched && LyricsStore.results.isEmpty()) Text(stringResource(R.string.no_results), color = Color.Gray, modifier = Modifier.padding(12.dp))
            LazyColumn {
                itemsIndexed(LyricsStore.results, key = { _, r -> r.id }) { _, result ->
                    Column(
                        Modifier.fillMaxWidth().clickable { LyricsStore.use(result, song); onDismiss() }.padding(vertical = 10.dp),
                    ) {
                        Text(result.track, color = Color.White, fontWeight = FontWeight.SemiBold)
                        val kind = stringResource(if (result.hasSynced) R.string.synced else R.string.plain)
                        Text("${result.artist} · ${formatTime((result.duration * 1000).toLong())} · $kind", color = Color.Gray, fontSize = 13.sp)
                    }
                    HorizontalDivider(color = Color.White.copy(alpha = 0.06f))
                }
            }
        }
    }
}

// MARK: File d'attente

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QueueSheet(onDismiss: () -> Unit) {
    val queue = PlayerConnection.queue
    val current = PlayerConnection.index
    val state = rememberLazyListState(initialFirstVisibleItemIndex = current.coerceAtLeast(0))
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color(0xFF16161A)) {
        Text(
            stringResource(R.string.queue), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        )
        LazyColumn(state = state, modifier = Modifier.height(520.dp)) {
            itemsIndexed(queue, key = { i, s -> "$i-${s.id}" }) { index, song ->
                Row(
                    Modifier.fillMaxWidth().clickable { PlayerConnection.jump(index) }.padding(horizontal = 16.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Artwork(song, 44.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            song.title, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            color = if (index == current) MaterialTheme.colorScheme.primary else if (index < current) Color.Gray else Color.White,
                            fontWeight = if (index == current) FontWeight.Bold else FontWeight.Normal,
                        )
                        Text(song.displayArtist, color = Color.Gray, fontSize = 12.sp, maxLines = 1)
                    }
                    if (index != current) {
                        IconButton(onClick = { PlayerConnection.removeAt(index) }) { Icon(Icons.Rounded.Close, null, tint = Color.Gray) }
                    }
                }
            }
        }
    }
}

// MARK: Minuterie et vitesse

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SleepSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color(0xFF16161A)) {
        Column(Modifier.padding(16.dp)) {
            Text(stringResource(R.string.sleep_timer), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            PlayerConnection.sleepEnd?.let { end ->
                val left = ((end - System.currentTimeMillis()) / 60000).coerceAtLeast(0)
                Text(stringResource(R.string.sleep_left, left.toInt()), color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(vertical = 6.dp))
            }
            listOf(5, 10, 15, 30, 45, 60, 90).forEach { minutes ->
                Text(
                    "$minutes min", color = Color.White, fontSize = 17.sp,
                    modifier = Modifier.fillMaxWidth().clickable { PlayerConnection.setSleepTimer(minutes); onDismiss() }.padding(vertical = 12.dp),
                )
            }
            if (PlayerConnection.sleepAtEnd) {
                Text(stringResource(R.string.sleep_end_on), color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(vertical = 6.dp))
            }
            Text(
                stringResource(R.string.sleep_end), color = Color.White, fontSize = 17.sp,
                modifier = Modifier.fillMaxWidth().clickable { PlayerConnection.setSleepTimer(-1); onDismiss() }.padding(vertical = 12.dp),
            )
            if (PlayerConnection.sleepEnd != null || PlayerConnection.sleepAtEnd) {
                Text(
                    stringResource(R.string.sleep_off), color = MaterialTheme.colorScheme.primary, fontSize = 17.sp,
                    modifier = Modifier.fillMaxWidth().clickable { PlayerConnection.setSleepTimer(0); onDismiss() }.padding(vertical = 12.dp),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SpeedSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color(0xFF16161A)) {
        Column(Modifier.padding(16.dp)) {
            val primary = MaterialTheme.colorScheme.primary
            Text(stringResource(R.string.speed_pitch), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.speed), color = Color.Gray, fontSize = 13.sp)
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f).forEach { value ->
                    val on = PlayerConnection.speed == value
                    Text(
                        "$value×".replace(".0×", "×"), color = if (on) Color.White else Color.White.copy(alpha = 0.85f),
                        fontWeight = FontWeight.Bold, fontSize = 14.sp,
                        modifier = Modifier.weight(1f).clip(RoundedCornerShape(50))
                            .background(if (on) primary else Color.White.copy(alpha = 0.1f))
                            .clickable { PlayerConnection.setSpeed(value) }.padding(vertical = 8.dp),
                        textAlign = TextAlign.Center,
                    )
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(stringResource(R.string.pitch), color = Color.Gray, fontSize = 13.sp)
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                val steps = PlayerConnection.semitones
                TextButton(onClick = { PlayerConnection.changePitch(steps - 1) }, enabled = steps > -6) { Text("−", fontSize = 24.sp) }
                Text(
                    if (steps > 0) "+$steps" else "$steps", color = primary, fontSize = 24.sp, fontWeight = FontWeight.Black,
                    textAlign = TextAlign.Center, modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { PlayerConnection.changePitch(steps + 1) }, enabled = steps < 6) { Text("+", fontSize = 24.sp) }
            }
            Text(stringResource(R.string.pitch_hint), color = Color.Gray, fontSize = 12.sp)
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TextButton(onClick = { PlayerConnection.cycleLoop() }, modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(
                            when {
                                PlayerConnection.loopA == null -> R.string.loop_set_a
                                PlayerConnection.loopB == null -> R.string.loop_set_b
                                else -> R.string.loop_stop
                            },
                        ),
                        textAlign = TextAlign.Center,
                    )
                }
                TextButton(
                    onClick = {
                        PlayerConnection.changePitch(0)
                        PlayerConnection.setSpeed(1f)
                        PlayerConnection.clearLoop()
                    },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.reset)) }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

/** Fiche du morceau : album, durée, format, taille, débit, écoutes, emplacement. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InfoSheet(song: Song, onDismiss: () -> Unit) {
    val size = remember(song.id) { runCatching { java.io.File(song.path).length() }.getOrDefault(0L) }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color(0xFF16161A)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Artwork(song, 64.dp, RoundedCornerShape(10.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(song.title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(song.displayArtist, color = Color.Gray, fontSize = 14.sp, maxLines = 1)
                }
            }
            Spacer(Modifier.height(12.dp))
            InfoRow(stringResource(R.string.info_album), song.album)
            if (song.track > 0) InfoRow(stringResource(R.string.info_track), "${song.track % 1000}")
            InfoRow(stringResource(R.string.info_duration), formatTime(song.duration))
            InfoRow(stringResource(R.string.info_format), song.path.substringAfterLast('.', "").uppercase())
            if (size > 0) {
                InfoRow(stringResource(R.string.info_size), android.text.format.Formatter.formatShortFileSize(LocalContext.current, size))
                if (song.duration > 0) InfoRow(stringResource(R.string.info_bitrate), "${size * 8 / song.duration} kbps")
            }
            InfoRow(stringResource(R.string.info_plays), "${MusicRepository.playCounts[song.id] ?: 0}")
            if (song.dateAdded > 0) {
                InfoRow(
                    stringResource(R.string.info_added),
                    java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date(song.dateAdded * 1000)),
                )
            }
            InfoRow(stringResource(R.string.info_location), song.path.substringBeforeLast('/', ""))
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = { PlayerConnection.playRadio(song); onDismiss() }) { Text(stringResource(R.string.radio_song)) }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    if (value.isBlank()) return
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp)) {
        Text(label, color = Color.Gray, fontSize = 14.sp, modifier = Modifier.width(130.dp))
        Text(value, color = Color.White, fontSize = 14.sp, modifier = Modifier.weight(1f), textAlign = TextAlign.End)
    }
}

// MARK: Égaliseur

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EqualizerSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color(0xFF16161A)) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.equalizer), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Switch(AudioFx.enabled, { AudioFx.setEnabled(it) })
            }
            if (AudioFx.bandCount == 0) {
                Text(stringResource(R.string.eq_unavailable), color = Color.Gray, modifier = Modifier.padding(vertical = 12.dp))
                return@Column
            }
            if (AudioFx.presets.isNotEmpty()) {
                androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 10.dp)) {
                    items(AudioFx.presets.size) { index ->
                        val selected = AudioFx.preset == index
                        Text(
                            AudioFx.presets[index],
                            color = if (selected) Color.White else Color.White.copy(alpha = 0.8f),
                            fontSize = 14.sp,
                            modifier = Modifier
                                .clip(RoundedCornerShape(20.dp))
                                .background(if (selected) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.1f))
                                .clickable { AudioFx.usePreset(index) }
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                        )
                    }
                }
            }
            AudioFx.levels.forEachIndexed { band, level ->
                val freq = AudioFx.bandFrequencies.getOrNull(band) ?: 0
                val label = if (freq >= 1000) "${freq / 1000} kHz" else "$freq Hz"
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(label, color = Color.Gray, fontSize = 12.sp, modifier = Modifier.width(64.dp))
                    Slider(
                        value = level.toFloat(),
                        onValueChange = { AudioFx.setLevel(band, it.toInt()) },
                        valueRange = AudioFx.range.first.toFloat()..AudioFx.range.last.toFloat(),
                        modifier = Modifier.weight(1f),
                    )
                    Text("%+.0f dB".format(level / 100f), color = Color.White, fontSize = 12.sp, modifier = Modifier.width(52.dp), textAlign = TextAlign.End)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.bass), color = Color.Gray, fontSize = 12.sp, modifier = Modifier.width(64.dp))
                Slider(AudioFx.bass.toFloat(), { AudioFx.setBass(it.toInt()) }, valueRange = 0f..1000f, modifier = Modifier.weight(1f))
                Text("${AudioFx.bass / 10}%", color = Color.White, fontSize = 12.sp, modifier = Modifier.width(52.dp), textAlign = TextAlign.End)
            }
            TextButton(onClick = { AudioFx.reset() }) { Text(stringResource(R.string.reset)) }
        }
    }
}
