package com.faxel.music.update

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.faxel.music.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Une mise à jour de l'historique (HISTORIQUE.json du dépôt, aussi intégré à l'app). */
class ChangeEntry(val date: String, val title: String, val time: Long, val lines: List<String>)

/**
 * Historique des nouveautés : intégré à l'app (tout ce qui est installé) et en ligne
 * (ce qu'apporte une nouvelle version, avant de l'installer).
 */
object Changelog {
    private var cache: List<ChangeEntry>? = null

    private fun parse(text: String): List<ChangeEntry> {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val list = mutableListOf<ChangeEntry>()
        try {
            val array = JSONArray(text)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val date = obj.optString("date")
                val items = obj.optJSONArray("items") ?: continue
                val lines = (0 until items.length()).mapNotNull { j ->
                    val item = items.getJSONObject(j)
                    val platform = item.optString("plateforme", "")
                    if (platform.isEmpty() || platform == "android") item.optString("texte") else null
                }.filter { it.isNotBlank() }
                if (lines.isEmpty()) continue
                val time = try { format.parse(date)?.time ?: 0L } catch (e: Exception) { 0L }
                list += ChangeEntry(date, obj.optString("titre", ""), time, lines)
            }
        } catch (e: Exception) {
        }
        return list.sortedByDescending { it.time }
    }

    fun bundled(context: Context): List<ChangeEntry> {
        cache?.let { return it }
        val text = try {
            context.assets.open("historique.json").bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            "[]"
        }
        return parse(text).also { cache = it }
    }

    suspend fun remote(): List<ChangeEntry> = withContext(Dispatchers.IO) {
        try {
            val c = URL("https://raw.githubusercontent.com/${Updater.REPO}/main/HISTORIQUE.json").openConnection() as HttpURLConnection
            c.connectTimeout = 15_000
            c.readTimeout = 15_000
            c.useCaches = false
            if (c.responseCode != 200) return@withContext emptyList()
            parse(c.inputStream.bufferedReader().use { it.readText() })
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Les mises à jour publiées après la compilation `build` (minutes depuis 1970). */
    fun since(build: Int, list: List<ChangeEntry>): List<ChangeEntry> = list.filter { it.time > build * 60_000L }

    fun day(entry: ChangeEntry): String =
        DateFormat.getDateInstance(DateFormat.LONG, Locale.getDefault()).format(Date(entry.time))
}

/** Une mise à jour et ses correctifs. */
@Composable
fun ChangeBlock(entry: ChangeEntry, dark: Boolean = true) {
    val text = if (dark) Color.White else Color.Unspecified
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        if (entry.title.isNotBlank()) Text(entry.title, color = text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        Text(Changelog.day(entry), color = Color.Gray, fontSize = 12.sp)
        Spacer(Modifier.height(6.dp))
        entry.lines.forEach { line ->
            Row(Modifier.padding(vertical = 3.dp), verticalAlignment = Alignment.Top) {
                Spacer(
                    Modifier.padding(top = 7.dp).size(6.dp).clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primary),
                )
                Spacer(Modifier.width(10.dp))
                Text(line, color = text, fontSize = 15.sp)
            }
        }
    }
}

/** Plein écran : tout l'historique (et ce que la prochaine version apportera). */
@Composable
fun ChangelogDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val installed = remember { Changelog.bundled(context) }
    var upcoming by remember { mutableStateOf<List<ChangeEntry>>(emptyList()) }
    LaunchedEffect(Unit) {
        upcoming = Changelog.since(Updater.currentBuild, Changelog.remote())
            .filter { up -> installed.none { it.date == up.date } }
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = Color(0xFF111114)) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.changelog_title), color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        Text(
                            AppName.get(context) + " " + Updater.currentVersion,
                            color = Color.Gray, fontSize = 13.sp,
                        )
                    }
                    TextButton(onClick = onDismiss) { Text(stringResource(R.string.changelog_close)) }
                }
                LazyColumn(
                    Modifier.fillMaxSize().padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (upcoming.isNotEmpty()) {
                        item {
                            Text(
                                stringResource(R.string.changelog_upcoming), color = Color(0xFFFFA726), fontSize = 13.sp,
                                modifier = Modifier.padding(top = 12.dp),
                            )
                        }
                        upcoming.forEach { entry -> item { ChangeBlock(entry) } }
                    }
                    if (installed.isEmpty() && upcoming.isEmpty()) {
                        item { Text(stringResource(R.string.changelog_empty), color = Color.Gray, modifier = Modifier.padding(top = 16.dp)) }
                    }
                    installed.forEach { entry -> item { ChangeBlock(entry) } }
                    item { Spacer(Modifier.height(40.dp)) }
                }
            }
        }
    }
}

/** Ligne des réglages « Historique des nouveautés ». */
@Composable
fun ChangelogRow() {
    var open by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable { open = true }.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.changelog_title), color = Color.White, fontSize = 16.sp)
            Text(stringResource(R.string.changelog_sub), color = Color.Gray, fontSize = 13.sp)
        }
    }
    if (open) ChangelogDialog(onDismiss = { open = false })
}

/** Après une mise à jour : ce qui a changé, puis la proposition de changer le nom de l'app. */
@Composable
fun WhatsNewDialog(entries: List<ChangeEntry>, onRename: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = Color(0xFF111114)) {
            Column(Modifier.fillMaxSize().padding(20.dp)) {
                Text(stringResource(R.string.appname_updated_title), color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
                Text(AppName.get(context) + " " + Updater.currentVersion, color = Color.Gray, fontSize = 14.sp)
                LazyColumn(Modifier.weight(1f).padding(top = 8.dp)) {
                    entries.forEach { entry -> item { ChangeBlock(entry) } }
                }
                Text(
                    stringResource(R.string.appname_updated_text, AppName.get(context)),
                    color = Color.Gray, fontSize = 13.sp, modifier = Modifier.padding(vertical = 8.dp),
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onRename) { Text(stringResource(R.string.appname_change)) }
                    TextButton(onClick = onDismiss) { Text(stringResource(R.string.changelog_continue)) }
                }
            }
        }
    }
}
