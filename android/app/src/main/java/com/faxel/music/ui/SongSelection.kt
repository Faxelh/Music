package com.faxel.music.ui

import android.app.RecoverableSecurityException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.PlaylistAdd
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.faxel.music.R
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Song
import com.faxel.music.playback.PlayerConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Sélection de plusieurs morceaux (une seule à la fois dans l'app). */
object SongSelection {
    val state = SelectionState()

    /** Copie les morceaux dans un dossier choisi. */
    suspend fun toFolder(context: Context, tree: Uri, songs: List<Song>): Int = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val parent = runCatching {
            DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        }.getOrNull() ?: return@withContext 0
        var count = 0
        for (song in songs) {
            val ok = runCatching {
                val name = song.path.substringAfterLast('/').ifBlank { song.title + ".mp3" }
                val mime = resolver.getType(song.uri) ?: "audio/*"
                val doc = DocumentsContract.createDocument(resolver, parent, mime, name) ?: error("doc")
                resolver.openOutputStream(doc)?.use { out ->
                    resolver.openInputStream(song.uri)?.use { it.copyTo(out) } ?: error("source")
                } ?: error("flux")
                true
            }.getOrDefault(false)
            if (ok) count++
        }
        count
    }

    fun share(context: Context, songs: List<Song>) {
        if (songs.isEmpty()) return
        val uris = ArrayList(songs.map { it.uri })
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        intent.type = "audio/*"
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        runCatching { context.startActivity(Intent.createChooser(intent, null)) }
    }

    fun setFavorites(songs: List<Song>) {
        val allFavorite = songs.all { MusicRepository.isFavorite(it) }
        songs.forEach { if (MusicRepository.isFavorite(it) == allFavorite) MusicRepository.toggleFavorite(it) }
    }
}

/**
 * Une page de morceaux avec le mode sélection : la barre du bas apparaît quand on
 * sélectionne (appui long sur un morceau, ou bouton « Sélectionner »).
 */
@Composable
fun SongSelectionHost(songs: List<Song>, content: @Composable () -> Unit) {
    val selection = SongSelection.state
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirm by remember { mutableStateOf(false) }
    var playlist by remember { mutableStateOf(false) }
    // On quitte la page : la sélection s'arrête.
    DisposableEffect(Unit) { onDispose { selection.finish() } }
    val chosen = songs.filter { selection.isSelected(it.key) }
    val folderDone = stringResource(R.string.sel_folder_done)
    val working = stringResource(R.string.sel_working)
    val deleted = stringResource(R.string.sel_deleted)
    var pendingDelete by remember { mutableStateOf<List<Song>>(emptyList()) }

    fun forgetAll(list: List<Song>) {
        list.forEach { song ->
            PlayerConnection.forget(song)
            MusicRepository.forget(song)
        }
        Toast.makeText(context, deleted.format(list.size), Toast.LENGTH_SHORT).show()
        selection.finish()
    }

    val deleteRequest = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        if (result.resultCode == android.app.Activity.RESULT_OK) {
            if (Build.VERSION.SDK_INT >= 30) {
                forgetAll(pendingDelete)
            } else {
                // Android 10 : l'accord ne fait qu'autoriser l'écriture, il faut encore supprimer.
                val resolver = context.contentResolver
                val done = pendingDelete.filter { song ->
                    runCatching { resolver.delete(song.uri, null, null) > 0 }.getOrDefault(false)
                }
                if (done.isNotEmpty()) forgetAll(done)
            }
        }
        pendingDelete = emptyList()
    }
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        if (tree != null) {
            val list = chosen
            Toast.makeText(context, working, Toast.LENGTH_SHORT).show()
            scope.launch {
                val count = SongSelection.toFolder(context, tree, list)
                Toast.makeText(context, folderDone.format(count), Toast.LENGTH_LONG).show()
                selection.finish()
            }
        }
    }

    fun delete(list: List<Song>) {
        pendingDelete = list
        val resolver = context.contentResolver
        if (Build.VERSION.SDK_INT >= 30) {
            // Android demande lui-même la confirmation pour supprimer les fichiers.
            val sender = MediaStore.createDeleteRequest(resolver, list.map { it.uri }).intentSender
            deleteRequest.launch(IntentSenderRequest.Builder(sender).build())
            return
        }
        val done = mutableListOf<Song>()
        for (song in list) {
            try {
                if (resolver.delete(song.uri, null, null) > 0) done += song
            } catch (e: SecurityException) {
                if (Build.VERSION.SDK_INT >= 29 && e is RecoverableSecurityException) {
                    pendingDelete = list - done.toSet()
                    if (done.isNotEmpty()) forgetAll(done)
                    deleteRequest.launch(IntentSenderRequest.Builder(e.userAction.actionIntent.intentSender).build())
                    return
                }
            }
        }
        if (done.isNotEmpty()) forgetAll(done)
        else Toast.makeText(context, context.getString(R.string.sel_delete_failed), Toast.LENGTH_LONG).show()
    }

    Box(Modifier.fillMaxSize()) {
        content()
        if (selection.active) {
            Box(Modifier.align(Alignment.BottomCenter)) {
                SelectionBar(
                    count = chosen.size,
                    total = songs.size,
                    onAll = { all -> selection.setAll(songs.map { it.key }, all) },
                    onDone = { selection.finish() },
                    actions = listOf(
                        SelectionAction(stringResource(R.string.sel_folder), Icons.Rounded.Folder, chosen.isNotEmpty()) { folderPicker.launch(null) },
                        SelectionAction(stringResource(R.string.sel_share), Icons.Rounded.Share, chosen.isNotEmpty()) {
                            SongSelection.share(context, chosen)
                        },
                        SelectionAction(stringResource(R.string.sel_playlist), Icons.Rounded.PlaylistAdd, chosen.isNotEmpty()) { playlist = true },
                        SelectionAction(stringResource(R.string.sel_queue), Icons.Rounded.QueueMusic, chosen.isNotEmpty()) {
                            PlayerConnection.addToQueue(chosen)
                            selection.finish()
                        },
                        SelectionAction(stringResource(R.string.sel_favorites), Icons.Rounded.Favorite, chosen.isNotEmpty()) {
                            SongSelection.setFavorites(chosen)
                            selection.finish()
                        },
                        SelectionAction(stringResource(R.string.sel_delete), Icons.Rounded.Delete, chosen.isNotEmpty(), destructive = true) {
                            confirm = true
                        },
                    ),
                )
            }
        }
    }
    if (playlist) {
        PlaylistPicker(songs = chosen, onDismiss = { playlist = false; selection.finish() })
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text(stringResource(R.string.sel_delete_title, chosen.size)) },
            text = { Text(stringResource(R.string.sel_delete_text)) },
            confirmButton = {
                TextButton(onClick = { confirm = false; delete(chosen) }) {
                    Text(stringResource(R.string.sel_delete), color = Color(0xFFFF5252))
                }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}
