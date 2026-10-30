package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import org.json.JSONObject

class AtlasCodingRepositories(
    private val request: (JSONObject, (Result<JSONObject>) -> Unit) -> Unit,
) {
    var listener: (() -> Unit)? = null
    var showing = false
    var catalog: JSONObject? = null
        private set
    var installation: String? = null
        private set
    var repository: String? = null
        private set
    var busy = false
        private set
    var message: String? = null
        private set
    private var generation = 0
    private var cleared = false
    val dirty: Boolean get() =
        catalog?.getJSONObject("settings")?.let {
            installation != it.nullableString("installation_id") || repository != it.nullableString("default_repository")
        } == true

    fun load() {
        if (busy || cleared) return
        fetch(if (dirty) installation else null, reset = !dirty)
    }

    fun chooseInstallation(id: String?) {
        if (busy || cleared) return
        installation = id
        repository = null
        catalog?.put("repositories", org.json.JSONArray())
        message = null
        if (id != null) fetch(id, reset = false) else listener?.invoke()
    }

    fun chooseRepository(name: String?) {
        if (busy || cleared) return
        repository = name
        message = null
        listener?.invoke()
    }

    private fun fetch(
        id: String?,
        reset: Boolean,
    ) {
        val current = ++generation
        busy = true
        listener?.invoke()
        val action = JSONObject().put("action", "repositories")
        if (id != null) action.put("installation_id", id)
        request(action) { result ->
            if (cleared || current != generation) return@request
            result.fold({ value ->
                catalog = value
                if (reset) {
                    installation = value.getJSONObject("settings").nullableString("installation_id")
                    repository = value.getJSONObject("settings").nullableString("default_repository")
                } else if (installation == null) {
                    catalog?.put("repositories", org.json.JSONArray())
                }
                message = null
            }, { message = it.message ?: "Could not load repositories. Your selection is kept." })
            busy = false
            listener?.invoke()
        }
    }

    fun save() {
        if (busy || cleared || catalog == null) return
        val current = ++generation
        busy = true
        listener?.invoke()
        request(
            JSONObject()
                .put("action", "update_repositories")
                .put("installation_id", installation ?: JSONObject.NULL)
                .put("default_repository", repository ?: JSONObject.NULL),
        ) { result ->
            if (cleared || current != generation) return@request
            result.fold({ saved ->
                catalog?.put("settings", saved)
                installation = saved.nullableString("installation_id")
                repository = saved.nullableString("default_repository")
                message = "Repository settings saved. Existing conversations are unchanged."
            }, { message = it.message ?: "Could not save. Your selection is kept; try again." })
            busy = false
            listener?.invoke()
        }
    }

    fun clear() {
        cleared = true
        generation++
        catalog = null
        installation = null
        repository = null
        listener = null
    }

    fun discard() {
        if (busy || cleared) return
        installation = catalog?.getJSONObject("settings")?.nullableString("installation_id")
        repository = catalog?.getJSONObject("settings")?.nullableString("default_repository")
        load()
    }
}

internal fun JSONObject.nullableString(key: String): String? = if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }

class AtlasCodingSettingsScreen(
    private val activity: Activity,
    private val model: AtlasCodingRepositories,
    private val dialog: (AlertDialog) -> Unit,
) {
    val view = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }

    init {
        text("Choose a GitHub App installation and a default repository for new private conversations on all your devices.")
        model.catalog?.let { catalog ->
            val installations = catalog.getJSONArray("installations")
            val choices =
                (0 until installations.length()).map {
                    installations.getJSONObject(it).let { row ->
                        row.getString("name") to row.getString("id")
                    }
                }
            val selected = choices.firstOrNull { it.second == model.installation }?.first ?: "None"
            button("GitHub installation: $selected") {
                dialog(
                    AtlasCodingChoices.show(activity, "GitHub installation", listOf("None" to null) + choices, model.installation) {
                        model.chooseInstallation(it)
                    },
                )
            }
            val repositories = catalog.getJSONArray("repositories")
            button("Default repository: ${model.repository ?: "None"}", model.installation != null) {
                val names = (0 until repositories.length()).map { repositories.getJSONObject(it).getString("full_name") }
                dialog(
                    AtlasCodingChoices.show(
                        activity,
                        "Default repository",
                        listOf("None" to null) + names.map { it to it },
                        model.repository,
                    ) {
                        model.chooseRepository(it)
                    },
                )
            }
            button("Save settings", model.dirty) { model.save() }
        }
        text("Only repositories available to both you and the GitHub App are listed. Choosing one does not clone it or enable a machine.")
        model.message?.let(::text)
        button(if (model.busy) "Loading repositories…" else "Refresh GitHub repositories") {
            model.load()
        }
    }

    private fun text(value: String) {
        view.addView(
            TextView(activity).apply {
                text = value
                textSize = 16f
                setPadding(0, 12, 0, 12)
            },
        )
    }

    private fun button(
        label: String,
        enabled: Boolean = true,
        action: () -> Unit,
    ) {
        view.addView(
            Button(activity).apply {
                text = label
                isAllCaps = false
                minHeight = (48 * resources.displayMetrics.density).toInt()
                isEnabled = enabled && !model.busy
                setOnClickListener { action() }
            },
            LinearLayout.LayoutParams(-1, -2),
        )
    }
}

internal object AtlasCodingChoices {
    fun show(
        activity: Activity,
        title: String,
        choices: List<Pair<String, String?>>,
        selected: String?,
        choose: (String?) -> Unit,
    ): AlertDialog {
        var filtered = choices
        val inset = (24 * activity.resources.displayMetrics.density).toInt()
        val search =
            EditText(activity).apply {
                hint = "Search"
                isSingleLine = true
                isSaveEnabled = false
                setPadding(0, paddingTop, 0, paddingBottom)
            }
        val list =
            object : ListView(activity) {
                override fun onMeasure(
                    widthMeasureSpec: Int,
                    heightMeasureSpec: Int,
                ) {
                    val maximum = (resources.displayMetrics.heightPixels * 0.45f).toInt()
                    val available =
                        if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED) {
                            maximum
                        } else {
                            minOf(maximum, MeasureSpec.getSize(heightMeasureSpec))
                        }
                    super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(available, MeasureSpec.AT_MOST))
                }
            }.apply {
                choiceMode = ListView.CHOICE_MODE_SINGLE
                setPadding(inset / 3, 0, inset / 3, 0)
            }
        val adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_single_choice, choices.map { it.first }.toMutableList())
        list.adapter = adapter
        list.setItemChecked(choices.indexOfFirst { it.second == selected }, true)
        search.addTextChangedListener(
            object : TextWatcher {
                override fun beforeTextChanged(
                    s: CharSequence?,
                    start: Int,
                    count: Int,
                    after: Int,
                ) = Unit

                override fun onTextChanged(
                    s: CharSequence?,
                    start: Int,
                    before: Int,
                    count: Int,
                ) {
                    filtered = choices.filter { it.first.contains(s.toString(), ignoreCase = true) }
                    adapter.clear()
                    adapter.addAll(filtered.map { it.first })
                    list.clearChoices()
                    list.setItemChecked(filtered.indexOfFirst { it.second == selected }, true)
                }

                override fun afterTextChanged(s: Editable?) = Unit
            },
        )
        val content =
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                isFocusableInTouchMode = true
                addView(search, LinearLayout.LayoutParams(-1, -2).apply { setMargins(inset, 0, inset, inset / 3) })
                addView(list, LinearLayout.LayoutParams(-1, -2))
            }
        val empty =
            TextView(activity).apply {
                text = "No repositories found"
                textSize = 16f
                setPadding(inset, inset / 2, inset, inset / 2)
                visibility = View.GONE
            }
        content.addView(empty)
        list.emptyView = empty
        val dialog =
            AlertDialog
                .Builder(activity)
                .setTitle(title)
                .setView(content)
                .setNegativeButton("Cancel", null)
                .create()
        list.setOnItemClickListener { _, _, index, _ ->
            choose(filtered[index].second)
            dialog.dismiss()
        }
        dialog.show()
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        return dialog
    }
}
