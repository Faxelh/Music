package com.faxel.music.ui

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.faxel.music.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Sélection de plusieurs éléments (clé = chemin du fichier). */
class SelectionState {
    var active by mutableStateOf(false)
    val keys = mutableStateListOf<String>()

    fun isSelected(key: String) = key in keys

    fun toggle(key: String) {
        if (key in keys) keys.remove(key) else keys.add(key)
    }

    fun start(key: String? = null) {
        active = true
        if (key != null && key !in keys) keys.add(key)
    }

    fun finish() {
        active = false
        keys.clear()
    }

    fun setAll(all: List<String>, selected: Boolean) {
        keys.clear()
        if (selected) keys.addAll(all)
    }
}

/** Copie de fichiers vers la galerie, un dossier choisi, ou partage. */
object Exporter {
    private fun mime(file: File): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"

    /** Ajoute à la galerie (Vidéos/Photos/Musique › Music). Renvoie le nombre de fichiers copiés. */
    suspend fun toGallery(context: Context, files: List<File>): Int = withContext(Dispatchers.IO) {
        var count = 0
        for (file in files) {
            if (!file.isFile) continue
            val type = mime(file)
            val ok = runCatching {
                if (Build.VERSION.SDK_INT >= 29) {
                    val (collection, folder) = when {
                        type.startsWith("video") -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_MOVIES
                        type.startsWith("image") -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_PICTURES
                        type.startsWith("audio") -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_MUSIC
                        else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI to Environment.DIRECTORY_DOWNLOADS
                    }
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                        put(MediaStore.MediaColumns.MIME_TYPE, type)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, "$folder/Music")
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val resolver = context.contentResolver
                    val uri = resolver.insert(collection, values) ?: error("uri")
                    resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: error("flux")
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                } else {
                    val base = when {
                        type.startsWith("video") -> Environment.DIRECTORY_MOVIES
                        type.startsWith("image") -> Environment.DIRECTORY_PICTURES
                        type.startsWith("audio") -> Environment.DIRECTORY_MUSIC
                        else -> Environment.DIRECTORY_DOWNLOADS
                    }
                    val folder = File(Environment.getExternalStoragePublicDirectory(base), "Music").apply { mkdirs() }
                    val target = File(folder, file.name)
                    file.copyTo(target, overwrite = true)
                    android.media.MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), null, null)
                }
                true
            }.getOrDefault(false)
            if (ok) count++
        }
        count
    }

    /** Copie dans un dossier choisi avec le sélecteur d'Android (carte SD, Téléchargements, Drive…). */
    suspend fun toFolder(context: Context, tree: Uri, files: List<File>): Int = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val parent = runCatching {
            DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        }.getOrNull() ?: return@withContext 0
        var count = 0
        for (file in files) {
            if (!file.isFile) continue
            val ok = runCatching {
                val doc = DocumentsContract.createDocument(resolver, parent, mime(file), file.name) ?: error("doc")
                resolver.openOutputStream(doc)?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: error("flux")
                true
            }.getOrDefault(false)
            if (ok) count++
        }
        count
    }

    fun share(context: Context, files: List<File>) {
        val uris = ArrayList<Uri>()
        files.filter { it.isFile }.forEach { file ->
            runCatching { uris += FileProvider.getUriForFile(context, context.packageName + ".files", file) }
        }
        if (uris.isEmpty()) return
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        intent.type = files.map { mime(it).substringBefore('/') }.distinct().singleOrNull()?.let { "$it/*" } ?: "*/*"
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        runCatching { context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }
}

/** Un bouton de la barre de sélection. */
class SelectionAction(
    val label: String,
    val icon: ImageVector,
    val enabled: Boolean = true,
    val destructive: Boolean = false,
    val onClick: () -> Unit,
)

/** Rond coché sur une vignette ou au début d'une ligne. */
@Composable
fun SelectionCheck(selected: Boolean, modifier: Modifier = Modifier) {
    val accentColor = MaterialTheme.colorScheme.primary
    Box(
        modifier.size(24.dp).clip(CircleShape)
            .background(if (selected) accentColor else Color.Black.copy(alpha = 0.35f))
            .border(2.dp, if (selected) accentColor else Color.White, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (selected) Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
    }
}

/** Barre du bas en mode sélection. */
@Composable
fun SelectionBar(count: Int, total: Int, onAll: (Boolean) -> Unit, onDone: () -> Unit, actions: List<SelectionAction>) {
    val allSelected = total > 0 && count >= total
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp))
            .background(Color(0xFF1C1C22)).navigationBarsPadding().padding(horizontal = 8.dp, vertical = 6.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { onAll(!allSelected) }) {
                Text(stringResource(if (allSelected) R.string.sel_none else R.string.sel_all))
            }
            Text(
                stringResource(R.string.sel_count, count), color = Color.Gray, fontSize = 13.sp,
                modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.sel_done)) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            actions.forEach { action ->
                val tint = when {
                    !action.enabled -> Color.Gray.copy(alpha = 0.5f)
                    action.destructive -> Color(0xFFFF5252)
                    else -> Color.White
                }
                Column(
                    Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                        .clickable(enabled = action.enabled, onClick = action.onClick).padding(vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(action.icon, null, tint = tint)
                    Spacer(Modifier.height(2.dp))
                    Text(action.label, color = tint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
        }
    }
}
