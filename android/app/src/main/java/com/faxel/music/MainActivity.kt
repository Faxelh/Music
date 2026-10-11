package com.faxel.music

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.faxel.music.data.MusicRepository
import com.faxel.music.playback.PlayerConnection
import com.faxel.music.ui.MusicRoot
import com.faxel.music.ui.MusicTheme

class MainActivity : AppCompatActivity() {
    private var granted by mutableStateOf(false)

    private val askPermissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        refreshPermission()
    }

    private val audioPermission: String
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        PlayerConnection.connect(this)
        refreshPermission()
        if (!granted) requestPermissions()
        setContent {
            MusicTheme {
                MusicRoot(granted = granted, onAskPermission = { requestPermissions() })
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshPermission()
    }

    override fun onStop() {
        super.onStop()
        PlayerConnection.saveState()
    }

    private fun requestPermissions() {
        val list = mutableListOf(audioPermission)
        if (Build.VERSION.SDK_INT >= 33) list += Manifest.permission.POST_NOTIFICATIONS
        askPermissions.launch(list.toTypedArray())
    }

    private fun refreshPermission() {
        val now = ContextCompat.checkSelfPermission(this, audioPermission) == PackageManager.PERMISSION_GRANTED
        if (now && (!granted || !MusicRepository.loaded)) MusicRepository.refresh()
        granted = now
    }
}
