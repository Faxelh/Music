package com.faxel.music.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.faxel.music.BuildConfig
import com.faxel.music.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Nouvelle version publiée sur GitHub (onglet « Releases », étiquette android-NUMÉRO). */
data class NewVersion(val number: Int, val title: String, val apkUrl: String, val notes: String) {
    /** Version affichée, ex. « 2026.1.3 » (dernier mot du titre de la Release). */
    val version: String get() = title.trim().substringAfterLast(' ')
}

/**
 * Mises à jour depuis GitHub, comme Elara : chaque compilation publie l'APK dans une Release.
 * L'app compare ce numéro au sien, télécharge l'APK et ouvre l'installateur d'Android.
 */
object Updater {
    const val REPO = "Faxelh/Music"

    var available by mutableStateOf<NewVersion?>(null); private set
    var checking by mutableStateOf(false); private set
    var downloading by mutableStateOf(false); private set
    var progress by mutableFloatStateOf(0f); private set
    var lastError by mutableStateOf<String?>(null); private set
    var checked by mutableStateOf(false); private set

    val currentBuild: Int get() = BuildConfig.VERSION_CODE
    val currentVersion: String get() = BuildConfig.VERSION_NAME

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("updates", Context.MODE_PRIVATE)

    /** Vérifie au plus une fois par jour, sauf si `force`. Renvoie la version plus récente, ou null. */
    suspend fun check(ctx: Context, force: Boolean = false): NewVersion? = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        val last = prefs(ctx).getLong("last", 0L)
        if (!force && now - last < 24 * 3600 * 1000L) return@withContext available
        checking = true
        lastError = null
        try {
            val c = URL("https://api.github.com/repos/$REPO/releases?per_page=20").openConnection() as HttpURLConnection
            c.setRequestProperty("Accept", "application/vnd.github+json")
            c.setRequestProperty("User-Agent", "Music-Android")
            c.connectTimeout = 15_000
            c.readTimeout = 15_000
            if (c.responseCode !in 200..299) throw Exception("GitHub : ${c.responseCode}")
            val list = JSONArray(c.inputStream.bufferedReader().readText())
            c.disconnect()
            var best: NewVersion? = null
            for (i in 0 until list.length()) {
                val r = list.getJSONObject(i)
                val tag = r.optString("tag_name")
                if (!tag.startsWith("android-")) continue
                val number = tag.removePrefix("android-").toIntOrNull() ?: continue
                val assets = r.optJSONArray("assets") ?: continue
                val apk = (0 until assets.length()).map { assets.getJSONObject(it) }
                    .firstOrNull { it.optString("name").endsWith(".apk") } ?: continue
                if (best == null || number > best.number) {
                    best = NewVersion(number, r.optString("name", tag), apk.optString("browser_download_url"), r.optString("body"))
                }
            }
            prefs(ctx).edit().putLong("last", now).apply()
            available = best?.takeIf { it.number > currentBuild }
            available
        } catch (e: Exception) {
            lastError = e.message ?: "?"
            null
        } finally {
            checking = false
            checked = true
        }
    }

    fun ignored(ctx: Context): Int = prefs(ctx).getInt("ignored", 0)
    fun ignore(ctx: Context, version: NewVersion) = prefs(ctx).edit().putInt("ignored", version.number).apply()

    /** Télécharge l'APK puis ouvre l'installateur d'Android. Renvoie false si une autorisation manque. */
    suspend fun install(ctx: Context, version: NewVersion): Boolean {
        // Android demande une fois l'autorisation « Installer des applis inconnues ».
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !ctx.packageManager.canRequestPackageInstalls()) {
            ctx.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.packageName))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return false
        }
        val file = withContext(Dispatchers.IO) {
            downloading = true
            progress = 0f
            lastError = null
            try {
                val folder = File(ctx.cacheDir, "maj").apply { mkdirs() }
                folder.listFiles()?.forEach { it.delete() }
                val dest = File(folder, "Music-${version.number}.apk")
                var address = version.apkUrl
                var c = URL(address).openConnection() as HttpURLConnection
                c.instanceFollowRedirects = false
                var hops = 0
                while (c.responseCode in 300..399 && hops < 6) {
                    address = c.getHeaderField("Location") ?: break
                    c.disconnect()
                    c = URL(address).openConnection() as HttpURLConnection
                    c.instanceFollowRedirects = false
                    hops++
                }
                val total = c.contentLengthLong
                c.inputStream.use { input ->
                    dest.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var received = 0L
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            output.write(buffer, 0, n)
                            received += n
                            if (total > 0) progress = received.toFloat() / total
                        }
                    }
                }
                c.disconnect()
                dest
            } catch (e: Exception) {
                lastError = e.message ?: "?"
                null
            } finally {
                downloading = false
            }
        } ?: return false
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", file)
        ctx.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return true
    }
}

/** Au démarrage : cherche une nouvelle version (une fois par jour) et la propose. */
@Composable
fun UpdateCheck() {
    AppNameAfterUpdate()
    val context = LocalContext.current
    var offered by remember { mutableStateOf<NewVersion?>(null) }
    LaunchedEffect(Unit) {
        val v = Updater.check(context)
        if (v != null && Updater.ignored(context) != v.number) offered = v
    }
    offered?.let { v ->
        UpdateDialog(v) { ignore ->
            if (ignore) Updater.ignore(context, v)
            offered = null
        }
    }
}

@Composable
fun UpdateDialog(version: NewVersion, close: (ignore: Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = { if (!Updater.downloading) close(false) },
        title = { Text(stringResource(R.string.upd_title)) },
        text = {
            Column {
                Text(stringResource(R.string.upd_text, version.version, Updater.currentVersion))
                if (version.notes.isNotBlank()) {
                    Spacer(Modifier.height(8.dp))
                    Text(version.notes.take(400), color = Color.Gray, fontSize = 13.sp)
                }
                if (Updater.downloading) {
                    Spacer(Modifier.height(12.dp))
                    LinearProgressIndicator(progress = { Updater.progress }, modifier = Modifier.fillMaxWidth())
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !Updater.downloading,
                onClick = {
                    scope.launch {
                        val ok = Updater.install(context, version)
                        when {
                            ok -> close(false)
                            Updater.lastError != null ->
                                Toast.makeText(context, context.getString(R.string.upd_error), Toast.LENGTH_LONG).show()
                            else -> Toast.makeText(context, context.getString(R.string.upd_allow), Toast.LENGTH_LONG).show()
                        }
                    }
                },
            ) { Text(stringResource(R.string.upd_install)) }
        },
        dismissButton = {
            TextButton(enabled = !Updater.downloading, onClick = { close(true) }) { Text(stringResource(R.string.upd_later)) }
        },
    )
}

/** Ligne des Réglages : version installée + « Rechercher une mise à jour ». */
@Composable
fun UpdateSettingsRow() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var found by remember { mutableStateOf<NewVersion?>(null) }
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(enabled = !Updater.checking) {
                scope.launch {
                    val v = Updater.check(context, force = true)
                    if (v != null) {
                        found = v
                    } else {
                        Toast.makeText(
                            context,
                            context.getString(if (Updater.lastError != null) R.string.upd_error else R.string.upd_uptodate),
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.upd_check), color = Color.White, fontSize = 16.sp)
            Text(
                stringResource(R.string.upd_installed, Updater.currentVersion),
                color = Color.Gray, fontSize = 13.sp,
            )
        }
        if (Updater.checking) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(4.dp))
        } else if (Updater.available != null) {
            Text(Updater.available!!.version, color = MaterialTheme.colorScheme.primary, fontSize = 14.sp)
        }
    }
    found?.let { v -> UpdateDialog(v) { found = null } }
}
