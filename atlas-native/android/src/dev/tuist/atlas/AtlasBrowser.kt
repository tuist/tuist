package dev.tuist.atlas

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import android.widget.Toolbar

internal fun Toolbar.browserAction(open: (() -> Unit)?) {
    if (open != null) {
        menu.add("Open in browser").setOnMenuItemClickListener {
            open()
            true
        }
    }
}

// Explicit browser components avoid handing a verified HTTPS URL straight back to Atlas.
internal fun Activity.openAtlasWebPage(
    url: String,
    noBrowserMessage: String,
) {
    val selector = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_BROWSER)
    val browsers =
        packageManager
            .queryIntentActivities(selector, 0)
            .map {
                ComponentName(it.activityInfo.packageName, it.activityInfo.name)
            }.filter { it.packageName != packageName && it.packageName != "android" }
            .distinct()
    val preferred = selector.resolveActivity(packageManager)?.takeIf { it in browsers }
    val intents =
        (preferred?.let(::listOf) ?: browsers).map { component ->
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).setComponent(component)
        }
    try {
        val intent = intents.firstOrNull() ?: throw ActivityNotFoundException()
        startActivity(
            if (intents.size == 1) {
                intent
            } else {
                Intent.createChooser(intent, "Open in browser").apply {
                    putExtra(Intent.EXTRA_INITIAL_INTENTS, intents.drop(1).toTypedArray())
                }
            },
        )
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(this, noBrowserMessage, Toast.LENGTH_LONG).show()
    }
}
