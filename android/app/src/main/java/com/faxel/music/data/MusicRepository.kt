package com.faxel.music.data

import android.content.Context
import android.provider.MediaStore
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Bibliothèque : morceaux du téléphone (MediaStore), favoris, playlists,
 * écoutes récentes et compteurs, gardés dans l'app.
 */
object MusicRepository {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var appContext: Context

    var songs by mutableStateOf<List<Song>>(emptyList())
        private set
    var loaded by mutableStateOf(false)
        private set
    var favorites by mutableStateOf<Set<Long>>(emptySet())
        private set
    var playlists by mutableStateOf<List<Playlist>>(emptyList())
        private set
    var recent by mutableStateOf<List<Long>>(emptyList())
        private set
    var playCounts by mutableStateOf<Map<Long, Int>>(emptyMap())
        private set
    /** Millisecondes écoutées par jour (« 2026-10-15 » → ms). */
    var listenDays by mutableStateOf<Map<String, Long>>(emptyMap())
        private set

    private val byId = HashMap<Long, Song>()

    fun init(context: Context) {
        appContext = context.applicationContext
        loadUserData()
    }

    fun song(id: Long): Song? = byId[id]

    fun refresh() {
        scope.launch {
            val found = withContext(Dispatchers.IO) { query() }
            val (groupedAlbums, groupedArtists) = withContext(Dispatchers.Default) {
                val a = found.groupBy { it.albumId }.map { (id, list) ->
                    Album(id, list.first().album.ifBlank { "—" }, list.first().displayArtist, list.sortedBy { it.track })
                }.sortedBy { it.title.lowercase() }
                val b = found.filter { it.hasArtist }.groupBy { it.artist }.map { (name, list) -> Artist(name, list) }
                    .sortedBy { it.name.lowercase() }
                a to b
            }
            byId.clear()
            found.forEach { byId[it.id] = it }
            songs = found
            albums = groupedAlbums
            artists = groupedArtists
            loaded = true
        }
    }

    private fun query(): List<Song> {
        val result = ArrayList<Song>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.TRACK,
        )
        val selection = "${MediaStore.Audio.Media.DURATION} >= 20000"
        try {
            appContext.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, null,
                "${MediaStore.Audio.Media.DATE_ADDED} DESC",
            )?.use { cursor ->
                val id = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val title = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val albumId = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val duration = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val data = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val added = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val track = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
                while (cursor.moveToNext()) {
                    val path = cursor.getString(data) ?: ""
                    val fallback = path.substringAfterLast('/').substringBeforeLast('.')
                    result += Song(
                        id = cursor.getLong(id),
                        title = cursor.getString(title)?.takeIf { it.isNotBlank() } ?: fallback,
                        artist = cursor.getString(artist) ?: "",
                        album = cursor.getString(album) ?: "",
                        albumId = cursor.getLong(albumId),
                        duration = cursor.getLong(duration),
                        path = path,
                        dateAdded = cursor.getLong(added),
                        track = cursor.getInt(track),
                    )
                }
            }
        } catch (_: SecurityException) {
        }
        return result
    }

    /** Albums et artistes calculés une seule fois par scan (listes fluides, même avec des milliers de morceaux). */
    var albums by mutableStateOf<List<Album>>(emptyList())
        private set
    var artists by mutableStateOf<List<Artist>>(emptyList())
        private set

    private fun group(list: List<Song>) {
        albums = list.groupBy { it.albumId }.map { (id, songs) ->
            Album(id, songs.first().album.ifBlank { "—" }, songs.first().displayArtist, songs.sortedBy { it.track })
        }.sortedBy { it.title.lowercase() }
        artists = list.filter { it.hasArtist }.groupBy { it.artist }.map { (name, songs) -> Artist(name, songs) }
            .sortedBy { it.name.lowercase() }
    }

    // MARK: Favoris, playlists, écoutes

    private val prefs get() = appContext.getSharedPreferences("user", Context.MODE_PRIVATE)

    private fun loadUserData() {
        val p = prefs
        favorites = p.getString("favorites", "")!!.split(',').mapNotNull { it.toLongOrNull() }.toSet()
        recent = p.getString("recent", "")!!.split(',').mapNotNull { it.toLongOrNull() }
        val counts = HashMap<Long, Int>()
        runCatching {
            val obj = JSONObject(p.getString("counts", "{}")!!)
            obj.keys().forEach { key -> key.toLongOrNull()?.let { counts[it] = obj.getInt(key) } }
        }
        playCounts = counts
        val days = HashMap<String, Long>()
        runCatching {
            val obj = JSONObject(p.getString("listen", "{}")!!)
            obj.keys().forEach { key -> days[key] = obj.getLong(key) }
        }
        listenDays = days
        val lists = ArrayList<Playlist>()
        runCatching {
            val array = JSONArray(p.getString("playlists", "[]"))
            for (i in 0 until array.length()) {
                val item = array.getJSONObject(i)
                val ids = item.getJSONArray("songs")
                lists += Playlist(item.getString("id"), item.getString("name"), (0 until ids.length()).map { ids.getLong(it) })
            }
        }
        playlists = lists
    }

    private fun save() {
        val counts = JSONObject()
        playCounts.forEach { (k, v) -> counts.put(k.toString(), v) }
        val array = JSONArray()
        playlists.forEach { list ->
            array.put(JSONObject().put("id", list.id).put("name", list.name).put("songs", JSONArray(list.songIds)))
        }
        prefs.edit()
            .putString("favorites", favorites.joinToString(","))
            .putString("recent", recent.joinToString(","))
            .putString("counts", counts.toString())
            .putString("playlists", array.toString())
            .putString("listen", JSONObject().also { obj -> listenDays.forEach { (k, v) -> obj.put(k, v) } }.toString())
            .apply()
    }

    fun isFavorite(song: Song) = song.id in favorites

    fun toggleFavorite(song: Song) {
        favorites = if (song.id in favorites) favorites - song.id else favorites + song.id
        save()
    }

    fun recordPlay(id: Long) {
        recent = (listOf(id) + recent.filter { it != id }).take(50)
        playCounts = playCounts + (id to ((playCounts[id] ?: 0) + 1))
        save()
    }

    // MARK: Statistiques et radio

    fun dayKey(millis: Long): String {
        val c = java.util.Calendar.getInstance().apply { timeInMillis = millis }
        return String.format(
            java.util.Locale.US, "%04d-%02d-%02d",
            c.get(java.util.Calendar.YEAR), c.get(java.util.Calendar.MONTH) + 1, c.get(java.util.Calendar.DAY_OF_MONTH),
        )
    }

    fun addListening(ms: Long) {
        if (ms <= 0) return
        val key = dayKey(System.currentTimeMillis())
        var days = listenDays + (key to ((listenDays[key] ?: 0L) + ms))
        if (days.size > 400) days = days.toSortedMap().entries.toList().takeLast(370).associate { it.key to it.value }
        listenDays = days
        save()
    }

    /** Minutes écoutées sur les `days` derniers jours (du plus ancien à aujourd'hui) : jour → minutes. */
    fun listeningMinutes(days: Int): List<Pair<Long, Double>> {
        val today = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 12)
            set(java.util.Calendar.MINUTE, 0)
        }.timeInMillis
        return (days - 1 downTo 0).map { back ->
            val day = today - back * 86_400_000L
            day to (listenDays[dayKey(day)] ?: 0L) / 60_000.0
        }
    }

    /** Jours d'écoute d'affilée (au moins 1 minute par jour). */
    val listeningStreak: Int
        get() {
            var day = System.currentTimeMillis()
            if ((listenDays[dayKey(day)] ?: 0L) < 60_000) day -= 86_400_000L
            var streak = 0
            while ((listenDays[dayKey(day)] ?: 0L) >= 60_000) {
                streak++
                day -= 86_400_000L
            }
            return streak
        }

    /** Radio d'un morceau : même artiste, album, dossier, vos favoris… puis un peu de hasard. */
    fun radio(seed: Song, count: Int = 60): List<Song> {
        val scored = songs.filter { it.id != seed.id }.map { song ->
            var score = Math.random() * 1.2
            if (seed.hasArtist && song.artist.equals(seed.artist, true)) score += 3
            if (song.albumId == seed.albumId) score += 1.2
            if (song.folder == seed.folder) score += 0.8
            if (song.id in favorites) score += 0.6
            score += minOf(1.0, (playCounts[song.id] ?: 0) / 10.0)
            song to score
        }
        val picks = scored.sortedByDescending { it.second }.take((count - 1).coerceAtLeast(0)).map { it.first }.shuffled()
        // Évite deux titres du même artiste à la suite.
        val pool = picks.toMutableList()
        val result = mutableListOf(seed)
        while (pool.isNotEmpty()) {
            val last = result.last().artist
            val index = pool.indexOfFirst { it.artist != last }.coerceAtLeast(0)
            result += pool.removeAt(index)
        }
        return result
    }

    fun createPlaylist(name: String, ids: List<Long>): Playlist {
        val list = Playlist(UUID.randomUUID().toString(), name.trim().ifBlank { "Playlist" }, ids)
        playlists = listOf(list) + playlists
        save()
        return list
    }

    fun createPlaylist(name: String): Playlist {
        val list = Playlist(UUID.randomUUID().toString(), name.trim().ifBlank { "Playlist" }, emptyList())
        playlists = listOf(list) + playlists
        save()
        return list
    }

    fun renamePlaylist(id: String, name: String) {
        playlists = playlists.map { if (it.id == id) it.copy(name = name.trim().ifBlank { it.name }) else it }
        save()
    }

    fun deletePlaylist(id: String) {
        playlists = playlists.filter { it.id != id }
        save()
    }

    fun addToPlaylist(id: String, songs: List<Song>) {
        playlists = playlists.map { list ->
            if (list.id == id) list.copy(songIds = list.songIds + songs.map { it.id }.filter { it !in list.songIds }) else list
        }
        save()
    }

    fun removeFromPlaylist(id: String, song: Song) {
        playlists = playlists.map { if (it.id == id) it.copy(songIds = it.songIds - song.id) else it }
        save()
    }

    fun playlistSongs(list: Playlist): List<Song> = list.songIds.mapNotNull { byId[it] }

    val favoriteSongs: List<Song> get() = songs.filter { it.id in favorites }
    val recentSongs: List<Song> get() = recent.mapNotNull { byId[it] }
    val mostPlayed: List<Song>
        get() = playCounts.entries.sortedByDescending { it.value }.mapNotNull { byId[it.key] }.take(25)

    /** Supprime le morceau du téléphone (demande la confirmation d'Android si besoin). */
    fun forget(song: Song) {
        byId.remove(song.id)
        songs = songs.filter { it.id != song.id }
        group(songs)
        favorites = favorites - song.id
        recent = recent.filter { it != song.id }
        playlists = playlists.map { it.copy(songIds = it.songIds - song.id) }
        save()
    }
}
