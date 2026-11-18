package dev.tuist.app.navigation

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.browser.customtabs.CustomTabsService

internal fun Context.openWebTab(url: String): Boolean {
    // Pin a Custom Tabs provider so verified app links cannot resolve back to MainActivity.
    val providers = packageManager.queryIntentServices(Intent(CustomTabsService.ACTION_CUSTOM_TABS_CONNECTION), 0)
        .map { it.serviceInfo.packageName }
    val browser = CustomTabsClient.getPackageName(this, providers) ?: return false
    return try {
        val tab = CustomTabsIntent.Builder().build()
        tab.intent.setPackage(browser)
        tab.launchUrl(this, Uri.parse(url))
        true
    } catch (_: ActivityNotFoundException) {
        false
    }
}
