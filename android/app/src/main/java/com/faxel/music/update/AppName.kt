package com.faxel.music.update

import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.faxel.music.R

/**
 * Nom de l'application choisi par l'utilisateur. Android ne laisse pas une app renommer
 * son icône installée : on enregistre le nom (utilisé dans l'app) et on pose sur l'écran
 * d'accueil une icône à ce nom (raccourci épinglé, renommé à chaque changement).
 */
object AppName {
    private const val SHORTCUT_ID = "app_name"

    private fun prefs(context: Context) = context.getSharedPreferences("app_name", Context.MODE_PRIVATE)

    fun default(context: Context): String = context.getString(R.string.app_name)

    fun get(context: Context): String =
        prefs(context).getString("name", null)?.trim()?.takeIf { it.isNotEmpty() } ?: default(context)

    fun set(context: Context, name: String) {
        val clean = name.trim().take(30)
        prefs(context).edit().putString("name", if (clean == default(context)) "" else clean).apply()
    }

    /** Pose (ou renomme) l'icône « nom » sur l'écran d'accueil. Faux si le lanceur ne le permet pas. */
    fun pinShortcut(context: Context, name: String, request: Boolean = true): Boolean {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply { action = Intent.ACTION_MAIN }
            ?: return false
        val label = name.trim().ifEmpty { default(context) }
        val info = ShortcutInfoCompat.Builder(context, SHORTCUT_ID)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
            .setIntent(launch)
            .build()
        val pinned = try {
            ShortcutManagerCompat.getShortcuts(context, ShortcutManagerCompat.FLAG_MATCH_PINNED)
                .any { it.id == SHORTCUT_ID }
        } catch (e: Exception) {
            false
        }
        if (pinned) {
            // Déjà sur l'écran d'accueil : il prend simplement le nouveau nom.
            return try { ShortcutManagerCompat.updateShortcuts(context, listOf(info)) } catch (e: Exception) { false }
        }
        if (!request || !ShortcutManagerCompat.isRequestPinShortcutSupported(context)) return false
        return try { ShortcutManagerCompat.requestPinShortcut(context, info, null) } catch (e: Exception) { false }
    }

    /** Vrai une seule fois après l'installation d'une nouvelle version. */
    fun justUpdated(context: Context): Boolean {
        val p = prefs(context)
        val last = p.getInt("build", 0)
        val now = Updater.currentBuild
        if (last != now) p.edit().putInt("build", now).apply()
        return last in 1 until now
    }
}

/** Ligne des réglages « Nom de l'application ». */
@Composable
fun AppNameRow() {
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    var current by remember { mutableStateOf(AppName.get(context)) }
    Row(
        Modifier.fillMaxWidth().clickable { open = true }.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.appname_title), color = Color.White, fontSize = 16.sp)
            Text(current, color = Color.Gray, fontSize = 13.sp)
        }
    }
    if (open) AppNameDialog(onDismiss = { open = false; current = AppName.get(context) })
}

/** Après une mise à jour : propose de changer le nom de l'app. */
@Composable
fun AppNameAfterUpdate() {
    val context = LocalContext.current
    var ask by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { ask = AppName.justUpdated(context) }
    if (ask) {
        AlertDialog(
            onDismissRequest = { ask = false },
            title = { Text(stringResource(R.string.appname_updated_title)) },
            text = { Text(stringResource(R.string.appname_updated_text, AppName.get(context))) },
            confirmButton = { TextButton(onClick = { ask = false; editing = true }) { Text(stringResource(R.string.appname_change)) } },
            dismissButton = { TextButton(onClick = { ask = false }) { Text(stringResource(R.string.appname_keep)) } },
        )
    }
    if (editing) AppNameDialog(onDismiss = { editing = false })
}

@Composable
fun AppNameDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    var name by remember { mutableStateOf(AppName.get(context)) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.appname_title)) },
        text = {
            Column {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(30) },
                    singleLine = true,
                    label = { Text(stringResource(R.string.appname_hint)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(10.dp))
                Text(stringResource(R.string.appname_home_info), color = Color.Gray, fontSize = 13.sp)
                Spacer(Modifier.height(10.dp))
                Button(
                    onClick = {
                        AppName.set(context, name)
                        val ok = AppName.pinShortcut(context, AppName.get(context))
                        Toast.makeText(
                            context,
                            context.getString(if (ok) R.string.appname_done else R.string.appname_unsupported),
                            Toast.LENGTH_LONG,
                        ).show()
                        onDismiss()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.appname_home)) }
                TextButton(onClick = { name = AppName.default(context) }) { Text(stringResource(R.string.appname_reset)) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                AppName.set(context, name)
                AppName.pinShortcut(context, AppName.get(context), request = false)
                Toast.makeText(context, context.getString(R.string.appname_done), Toast.LENGTH_SHORT).show()
                onDismiss()
            }) { Text(stringResource(R.string.appname_save)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
