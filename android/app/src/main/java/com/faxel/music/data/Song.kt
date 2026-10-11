package com.faxel.music.data

import android.content.ContentUris
import android.net.Uri
import android.provider.MediaStore

/** Un morceau de la bibliothèque du téléphone (MediaStore). */
data class Song(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val albumId: Long,
    val duration: Long,
    val path: String,
    val dateAdded: Long,
    val track: Int,
) {
    val uri: Uri
        get() = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)

    val artUri: Uri
        get() = ContentUris.withAppendedId(Uri.parse("content://media/external/audio/albumart"), albumId)

    val key: String get() = id.toString()

    val folder: String
        get() = path.substringBeforeLast('/', "").substringAfterLast('/', "")

    val hasArtist: Boolean get() = artist.isNotBlank() && artist != "<unknown>"

    val displayArtist: String get() = if (hasArtist) artist else ""
}

data class Album(val id: Long, val title: String, val artist: String, val songs: List<Song>) {
    val artUri: Uri get() = songs.first().artUri
}

data class Artist(val name: String, val songs: List<Song>) {
    val albums: Int get() = songs.map { it.albumId }.distinct().size
}

data class Playlist(val id: String, val name: String, val songIds: List<Long>)
