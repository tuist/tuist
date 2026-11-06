package dev.tuist.atlas.preview

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import dev.tuist.atlas.AtlasCore
import dev.tuist.atlas.AtlasWorkspaceModel
import dev.tuist.atlas.AtlasWorkspaceScreen

class WorkspacePreviewActivity : Activity() {
    private lateinit var model: AtlasWorkspaceModel
    private lateinit var screen: AtlasWorkspaceScreen
    private var unregisterBack: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkWorkspaceModel()
        val core = AtlasCore()
        model = lastNonConfigurationInstance as? AtlasWorkspaceModel
            ?: AtlasWorkspaceModel(core.groups(), core.sections(), savedInstanceState?.getString("group"))
        screen =
            AtlasWorkspaceScreen(this, model, "atlas.example.org", { section ->
                if (section.screen == "time-off") {
                    startActivity(Intent(this, TimeOffPreviewActivity::class.java))
                } else {
                    AlertDialog
                        .Builder(this)
                        .setTitle("Link preview")
                        .setMessage(section.destination("https://atlas.example.org").toString())
                        .setPositiveButton("Done", null)
                        .show()
                }
            }, { updateBack() })
        setActionBar(screen.toolbar)
        setContentView(screen.view)
        updateBack()
    }

    override fun onRetainNonConfigurationInstance(): Any = model

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("group", model.groupId)
        super.onSaveInstanceState(outState)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, 1, 0, "Settings").setIcon(android.R.drawable.ic_menu_preferences).setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean =
        when (item.itemId) {
            1 -> {
                startActivity(Intent(this, SettingsPreviewActivity::class.java))
                true
            }
            android.R.id.home -> {
                screen.back()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!screen.back()) super.onBackPressed()
    }

    override fun onDestroy() {
        screen.close()
        unregisterBack?.invoke()
        super.onDestroy()
    }

    private fun updateBack() {
        actionBar?.setDisplayHomeAsUpEnabled(model.canBack)
        unregisterBack?.invoke()
        unregisterBack = null
        if (Build.VERSION.SDK_INT >= 33 && model.canBack) {
            val callback = OnBackInvokedCallback { screen.back() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
            unregisterBack = { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
        }
    }
}
