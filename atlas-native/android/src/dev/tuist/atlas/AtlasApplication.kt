package dev.tuist.atlas

import android.app.Application

class AtlasApplication : Application() {
    val authentication: AtlasAuthentication by lazy { AtlasAuthentication(this) }
}
