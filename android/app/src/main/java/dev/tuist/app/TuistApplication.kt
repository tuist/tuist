package dev.tuist.app

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class TuistApplication : Application() {
    companion object {
        const val APP_TAG = "TuistApp"
    }
}
