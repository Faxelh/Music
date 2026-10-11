package com.faxel.music.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class LyricLine(val id: Int, val time: Double?, val text: String)

data class Lyrics(val lines: List<LyricLine>, val source: String) {
    val isSynced: Boolean get() = lines.any { it.time != null }

    fun currentIndex(seconds: Double): Int? {
        var found: Int? = null
        for ((index, line) in lines.withIndex()) {
            val time = line.time ?: continue
            if (time <= seconds + 0.15) found = index else break
        }
        return found
    }

    val lrc: String
        get() = lines.joinToString("\n") { line ->
            val time = line.time ?: return@joinToString line.text
            val minutes = (time / 60).toInt()
            "[%02d:%05.2f]".format(java.util.Locale.US, minutes, time - minutes * 60) + line.text
        }
}

data class OnlineLyrics(
    val id: Int,
    val track: String,
    val artist: String,
    val duration: Double,
    val synced: String?,
    val plain: String?,
) {
    val hasSynced: Boolean get() = !synced.isNullOrBlank()
}

object LyricsParser {
    private val tag = Regex("""^\[(\d{1,2}):(\d{1,2}(?:[.,]\d{1,3})?)\]""")

    fun parse(raw: String): List<LyricLine> {
        val timed = ArrayList<Pair<Double, String>>()
        val plain = ArrayList<String>()
        for (rawLine in raw.replace("\r\n", "\n").replace('\r', '\n').split('\n')) {
            var line = rawLine.trim()
            val times = ArrayList<Double>()
            while (true) {
                val match = tag.find(line) ?: break
                val minutes = match.groupValues[1].toDouble()
                val seconds = match.groupValues[2].replace(',', '.').toDouble()
                times += minutes * 60 + seconds
                line = line.substring(match.range.last + 1)
            }
            if (times.isEmpty()) {
                if (!line.startsWith("[")) plain += line
            } else {
                times.forEach { timed += it to line.trim() }
            }
        }
        if (timed.isNotEmpty()) {
            return timed.sortedBy { it.first }.mapIndexed { index, pair -> LyricLine(index, pair.first, pair.second) }
        }
        while (plain.firstOrNull()?.isEmpty() == true) plain.removeAt(0)
        while (plain.lastOrNull()?.isEmpty() == true) plain.removeAt(plain.size - 1)
        return plain.mapIndexed { index, text -> LyricLine(index, null, text) }
    }
}

/** Paroles : gardées dans l'app, fichier .lrc à côté du son, ou LRCLIB (synchronisées). */
object LyricsStore {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var folder: File

    var lyrics by mutableStateOf<Lyrics?>(null)
        private set
    var songId by mutableStateOf<Long?>(null)
        private set
    var loading by mutableStateOf(false)
        private set
    var searching by mutableStateOf(false)
        private set
    var searched by mutableStateOf(false)
        private set
    var results by mutableStateOf<List<OnlineLyrics>>(emptyList())
        private set

    fun init(context: Context) {
        folder = File(context.filesDir, "lyrics").apply { mkdirs() }
    }

    private fun saved(song: Song) = File(folder, "${song.id}.lrc")

    fun load(song: Song, autoSearch: Boolean) {
        if (songId == song.id) return
        songId = song.id
        lyrics = null
        results = emptyList()
        searched = false
        loading = true
        scope.launch {
            val found = withContext(Dispatchers.IO) { local(song) }
            if (songId != song.id) return@launch
            lyrics = found
            loading = false
            if (found == null && autoSearch) fetchBest(song)
        }
    }

    private fun local(song: Song): Lyrics? {
        runCatching {
            val file = saved(song)
            if (file.exists()) {
                val lines = LyricsParser.parse(file.readText())
                if (lines.isNotEmpty()) return Lyrics(lines, "saved")
            }
        }
        runCatching {
            val sibling = File(song.path.substringBeforeLast('.') + ".lrc")
            if (sibling.exists()) {
                val lines = LyricsParser.parse(sibling.readText())
                if (lines.isNotEmpty()) return Lyrics(lines, "file")
            }
        }
        return null
    }

    fun save(lyrics: Lyrics, song: Song) {
        runCatching { saved(song).writeText(lyrics.lrc) }
        if (songId == song.id) this.lyrics = lyrics
    }

    fun delete(song: Song) {
        saved(song).delete()
        songId = null
        load(song, autoSearch = false)
    }

    /** « Artiste - Titre (Official Video) » → (titre, artiste). */
    fun guess(song: Song): Pair<String, String?> {
        var title = cleanTitle(song.title)
        var artist: String? = song.displayArtist.ifBlank { null }
        val dash = title.indexOf(" - ")
        if (dash > 0) {
            val left = title.substring(0, dash).trim()
            val right = title.substring(dash + 3).trim()
            if (left.isNotEmpty() && right.isNotEmpty()) {
                if (artist == null) artist = left
                title = right
            }
        }
        return title to artist
    }

    fun cleanTitle(title: String): String {
        var text = title
        text = text.replace(Regex("""\([^)]*\)"""), "").replace(Regex("""\[[^\]]*\]"""), "")
        listOf(" feat", " ft.", " ft ", "|").forEach { marker ->
            val index = text.indexOf(marker, ignoreCase = true)
            if (index > 0) text = text.substring(0, index)
        }
        return text.trim()
    }

    fun search(song: Song, query: String? = null, done: (() -> Unit)? = null) {
        val (title, artist) = guess(song)
        val params = if (!query.isNullOrBlank()) {
            "q=" + enc(query)
        } else {
            "track_name=" + enc(title) + (artist?.let { "&artist_name=" + enc(it) } ?: "")
        }
        searching = true
        scope.launch {
            val found = withContext(Dispatchers.IO) { request(params) }
            val seconds = song.duration / 1000.0
            results = found.sortedWith(compareBy<OnlineLyrics>({ !it.hasSynced }, { kotlin.math.abs(it.duration - seconds) }))
            searching = false
            searched = true
            done?.invoke()
        }
    }

    private fun enc(text: String) = URLEncoder.encode(text, "UTF-8")

    private fun request(params: String): List<OnlineLyrics> = runCatching {
        val connection = URL("https://lrclib.net/api/search?$params").openConnection() as HttpURLConnection
        connection.connectTimeout = 15000
        connection.readTimeout = 15000
        connection.setRequestProperty("User-Agent", "Music Android 1.0 (https://github.com/Faxelh)")
        val text = connection.inputStream.bufferedReader().use { it.readText() }
        val array = JSONArray(text)
        (0 until array.length()).mapNotNull { index ->
            val item = array.getJSONObject(index)
            val synced = item.optString("syncedLyrics").takeIf { it.isNotBlank() && it != "null" }
            val plain = item.optString("plainLyrics").takeIf { it.isNotBlank() && it != "null" }
            if (synced == null && plain == null) return@mapNotNull null
            OnlineLyrics(item.optInt("id"), item.optString("trackName"), item.optString("artistName"),
                item.optDouble("duration", 0.0), synced, plain)
        }
    }.getOrDefault(emptyList())

    fun fetchBest(song: Song) {
        val seconds = song.duration / 1000.0
        search(song) {
            if (songId != song.id || lyrics != null) return@search
            val best = results.firstOrNull()
            if (best != null && (best.duration <= 0 || kotlin.math.abs(best.duration - seconds) < 8)) {
                use(best, song)
            } else if (results.isEmpty()) {
                search(song, guess(song).first) {
                    val second = results.firstOrNull() ?: return@search
                    if (songId == song.id && lyrics == null &&
                        (second.duration <= 0 || kotlin.math.abs(second.duration - seconds) < 5)) use(second, song)
                }
            }
        }
    }

    fun use(result: OnlineLyrics, song: Song) {
        val text = if (result.hasSynced) result.synced!! else result.plain ?: return
        val lines = LyricsParser.parse(text)
        if (lines.isNotEmpty()) save(Lyrics(lines, "online"), song)
    }
}
