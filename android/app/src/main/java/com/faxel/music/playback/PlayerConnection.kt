package com.faxel.music.playback

import android.content.ComponentName
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Song
import com.google.common.util.concurrent.ListenableFuture

/** Lien entre l'interface et le service de lecture (file, lecture, aléatoire, répétition…). */
object PlayerConnection {
    private var future: ListenableFuture<MediaController>? = null
    private lateinit var appContext: Context

    var controller by mutableStateOf<MediaController?>(null)
        private set
    var currentId by mutableStateOf<Long?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var queueIds by mutableStateOf<List<Long>>(emptyList())
        private set
    var index by mutableStateOf(0)
        private set
    var shuffle by mutableStateOf(false)
        private set
    var repeatMode by mutableStateOf(Player.REPEAT_MODE_OFF)
        private set
    var speed by mutableStateOf(1f)
        private set
    var sleepEnd by mutableStateOf<Long?>(null)
        private set

    private val sleepHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val sleepRunnable = Runnable {
        controller?.pause()
        sleepEnd = null
    }

    val current: Song? get() = currentId?.let { MusicRepository.song(it) }
    val queue: List<Song> get() = queueIds.mapNotNull { MusicRepository.song(it) }

    fun connect(context: Context) {
        appContext = context.applicationContext
        if (future != null) return
        val token = SessionToken(appContext, ComponentName(appContext, PlaybackService::class.java))
        val pending = MediaController.Builder(appContext, token).buildAsync()
        future = pending
        pending.addListener({
            val ready = runCatching { pending.get() }.getOrNull() ?: return@addListener
            controller = ready
            ready.addListener(listener)
            sync()
            restoreIfEmpty()
        }, ContextCompat.getMainExecutor(appContext))
    }

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            sync()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            mediaItem?.mediaId?.toLongOrNull()?.let { MusicRepository.recordPlay(it) }
            saveState()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (!isPlaying) saveState()
        }
    }

    private fun sync() {
        val c = controller ?: return
        isPlaying = c.isPlaying
        currentId = c.currentMediaItem?.mediaId?.toLongOrNull()
        index = c.currentMediaItemIndex
        shuffle = c.shuffleModeEnabled
        repeatMode = c.repeatMode
        speed = c.playbackParameters.speed
        val ids = ArrayList<Long>(c.mediaItemCount)
        for (i in 0 until c.mediaItemCount) {
            c.getMediaItemAt(i).mediaId.toLongOrNull()?.let { ids += it }
        }
        if (ids != queueIds) queueIds = ids
    }

    private fun item(song: Song): MediaItem = MediaItem.Builder()
        .setMediaId(song.id.toString())
        .setUri(song.uri)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(song.title)
                .setArtist(song.displayArtist)
                .setAlbumTitle(song.album)
                .setArtworkUri(song.artUri)
                .build(),
        )
        .build()

    fun play(songs: List<Song>, start: Int = 0, shuffled: Boolean = false) {
        val c = controller ?: return
        if (songs.isEmpty()) return
        c.shuffleModeEnabled = shuffled
        c.setMediaItems(songs.map { item(it) }, if (shuffled) (songs.indices).random() else start.coerceIn(songs.indices), 0L)
        c.prepare()
        c.play()
    }

    fun toggle() {
        val c = controller ?: return
        if (c.isPlaying) c.pause() else {
            if (c.playbackState == Player.STATE_IDLE) c.prepare()
            if (c.playbackState == Player.STATE_ENDED) c.seekTo(0)
            c.play()
        }
    }

    fun next() = controller?.seekToNext()
    fun previous() = controller?.seekToPrevious()
    fun seek(ms: Long) = controller?.seekTo(ms)
    fun jump(to: Int) {
        controller?.seekTo(to, 0L)
        controller?.play()
    }

    fun toggleShuffle() {
        controller?.let { it.shuffleModeEnabled = !it.shuffleModeEnabled }
    }

    fun cycleRepeat() {
        val c = controller ?: return
        c.repeatMode = when (c.repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
    }

    @JvmName("updateSpeed")
    fun setSpeed(value: Float) {
        controller?.playbackParameters = PlaybackParameters(value)
    }

    fun playNext(song: Song) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) return play(listOf(song))
        c.addMediaItem((c.currentMediaItemIndex + 1).coerceAtMost(c.mediaItemCount), item(song))
    }

    fun addToQueue(songs: List<Song>) {
        val c = controller ?: return
        if (c.mediaItemCount == 0) return play(songs)
        c.addMediaItems(songs.map { item(it) })
    }

    fun removeAt(position: Int) {
        val c = controller ?: return
        if (position != c.currentMediaItemIndex && position in 0 until c.mediaItemCount) c.removeMediaItem(position)
    }

    fun move(from: Int, to: Int) {
        controller?.moveMediaItem(from, to)
    }

    fun forget(song: Song) {
        val c = controller ?: return
        for (i in c.mediaItemCount - 1 downTo 0) {
            if (c.getMediaItemAt(i).mediaId == song.id.toString()) c.removeMediaItem(i)
        }
    }

    fun setSleepTimer(minutes: Int) {
        sleepHandler.removeCallbacks(sleepRunnable)
        if (minutes <= 0) {
            sleepEnd = null
            return
        }
        sleepEnd = System.currentTimeMillis() + minutes * 60_000L
        sleepHandler.postDelayed(sleepRunnable, minutes * 60_000L)
    }

    // MARK: Reprise au lancement

    private fun prefs() = appContext.getSharedPreferences("queue", Context.MODE_PRIVATE)

    fun saveState() {
        val c = controller ?: return
        if (c.mediaItemCount == 0) return
        prefs().edit()
            .putString("ids", queueIds.joinToString(","))
            .putInt("index", c.currentMediaItemIndex)
            .putLong("position", c.currentPosition)
            .apply()
    }

    /** Retrouve la file et la position de la dernière fois (en pause). */
    fun restoreIfEmpty() {
        val c = controller ?: return
        if (c.mediaItemCount > 0 || !MusicRepository.loaded) return
        val p = prefs()
        val songs = p.getString("ids", "")!!.split(',').mapNotNull { it.toLongOrNull() }
            .mapNotNull { MusicRepository.song(it) }
        if (songs.isEmpty()) return
        val start = p.getInt("index", 0).coerceIn(songs.indices)
        c.setMediaItems(songs.map { item(it) }, start, p.getLong("position", 0L))
        c.prepare()
    }
}
