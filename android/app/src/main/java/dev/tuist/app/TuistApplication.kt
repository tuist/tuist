package dev.tuist.app

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.serviceLoaderEnabled
import dagger.hilt.android.HiltAndroidApp
import dev.tuist.app.data.network.CertificateTrust
import dev.tuist.app.data.push.FirebaseSetup
import dev.tuist.app.data.push.NotificationChannels

@HiltAndroidApp
class TuistApplication : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        NotificationChannels.create(this)
        FirebaseSetup.initialize(this)
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader = ImageLoader.Builder(context)
        .serviceLoaderEnabled(false)
        .components {
            add(OkHttpNetworkFetcherFactory(callFactory = { CertificateTrust.clientBuilder().build() }))
        }
        .build()
}
