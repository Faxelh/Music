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

    private val byId = HashMap<Long, Song>()

    fun init(context: Context) {
        appContext = context.applicationContext
        loadUserData()
    }

    fun song(id: Long): Song? = byId[id]

    fun refresh() {
        scope.launch {
            val found = withContext(Dispatchers.IO) { query() }
            byId.clear()
            found.forEach { byId[it.id] = it }
            songs = found
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

    val albums: List<Album>
        get() = songs.groupBy { it.albumId }.map { (id, list) ->
            Album(id, list.first().album.ifBlank { "—" }, list.first().displayArtist, list.sortedBy { it.track })
        }.sortedBy { it.title.lowercase() }

    val artists: List<Artist>
        get() = songs.filter { it.hasArtist }.groupBy { it.artist }.map { (name, list) -> Artist(name, list) }
            .sortedBy { it.name.lowercase() }

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
        favorites = favorites - song.id
        recent = recent.filter { it != song.id }
        playlists = playlists.map { it.copy(songIds = it.songIds - song.id) }
        save()
    }
}
