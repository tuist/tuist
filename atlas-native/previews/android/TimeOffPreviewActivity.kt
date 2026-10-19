package dev.tuist.atlas.preview

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.MenuItem
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import dev.tuist.atlas.AtlasCore
import dev.tuist.atlas.AtlasTimeOffModel
import dev.tuist.atlas.AtlasTimeOffScreen
import org.json.JSONArray
import org.json.JSONObject

class TimeOffPreviewActivity : Activity() {
    private lateinit var model: AtlasTimeOffModel
    private lateinit var screen: AtlasTimeOffScreen
    private var unregisterBack: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkTimeOffModel()
        model = lastNonConfigurationInstance as? AtlasTimeOffModel ?: fixture()
        screen = AtlasTimeOffScreen(this, AtlasCore().sections().first { it.screen == "time-off" }.title, model)
        setActionBar(screen.toolbar)
        actionBar?.setDisplayHomeAsUpEnabled(true)
        setContentView(screen.view)
        if (Build.VERSION.SDK_INT >= 33) {
            val callback = OnBackInvokedCallback { if (!screen.back()) finish() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
            unregisterBack = { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
        }
        screen.load()
    }

    override fun onRetainNonConfigurationInstance(): Any = model

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!screen.back()) super.onBackPressed()
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId != android.R.id.home) return super.onOptionsItemSelected(item)
        if (!screen.back()) finish()
        return true
    }

    override fun onDestroy() {
        screen.close()
        unregisterBack?.invoke()
        super.onDestroy()
    }

    private fun fixture(): AtlasTimeOffModel {
        val main = Handler(Looper.getMainLooper())
        val failSave = intent.getBooleanExtra("fail-save", false)
        val rows =
            mutableListOf(
                JSONObject(
                    """{"id":"preview","starts_on":"2027-06-07","ends_on":"2027-06-11","status":"pending","working_days":5,"missing_years":[]}""",
                ),
            )
        return AtlasTimeOffModel { action, complete ->
            main.post {
                val operation = action.getString("action")
                if (operation == "list") {
                    complete(
                        Result.success(
                            JSONObject()
                                .put("requests", JSONObject().put("items", JSONArray(rows)).put("page", 1).put("total_pages", 1))
                                .put(
                                    "public_holidays",
                                    JSONObject()
                                        .put(
                                            "items",
                                            JSONArray("""[{"name":"Christmas Day","date":"2027-12-25"}]"""),
                                        ).put("page", 1)
                                        .put("total_pages", 1),
                                ),
                        ),
                    )
                } else if (failSave) {
                    complete(Result.failure(IllegalStateException("Preview save failed. Your dates are still here.")))
                } else {
                    val id = action.optString("id")
                    if (operation == "cancel") {
                        rows.firstOrNull { it.getString("id") == id }?.put("status", "cancelled")
                    } else {
                        val value =
                            JSONObject(
                                action.toString(),
                            ).put("id", id.ifEmpty { "new-preview" }).put("status", "pending").put("working_days", 5)
                        rows.removeAll { it.getString("id") == id }
                        rows.add(0, value)
                    }
                    complete(Result.success(JSONObject()))
                }
            }
        }
    }
}
