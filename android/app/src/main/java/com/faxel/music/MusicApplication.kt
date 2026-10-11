package com.faxel.music

import android.app.Application
import com.faxel.music.data.LyricsStore
import com.faxel.music.data.MusicRepository
import com.faxel.music.data.Settings
import com.faxel.music.playback.AudioFx

class MusicApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Settings.init(this)
        MusicRepository.init(this)
        LyricsStore.init(this)
        AudioFx.init(this)
    }
}
