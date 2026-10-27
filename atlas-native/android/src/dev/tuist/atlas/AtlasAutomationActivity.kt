package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.util.Calendar
import java.util.UUID

class AtlasAutomationActivity : Activity() {
    private class State {
        var session = -1
        var section = "workflows"
        var mode = "list"
        var id = ""
        var page = 1
        var data: JSONObject? = null
        val values = mutableMapOf<String, String>()
        var launch: JSONObject? = null
    }

    private lateinit var authentication: AtlasAuthentication
    private var state = State()
    private lateinit var content: LinearLayout
    private lateinit var scroll: ScrollView
    private val handler = Handler(Looper.getMainLooper())

    @Volatile private var generation = 0

    @Volatile private var visible = false
    private var busy = false
    private var error: String? = null
    private var authenticationListener: (() -> Unit)? = null
    private val terminal = setOf("succeeded", "failed", "rejected", "cancelled")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        authentication = (application as AtlasApplication).authentication
        state = (lastNonConfigurationInstance as? State) ?: State()
    }

    override fun onRetainNonConfigurationInstance(): Any = state

    override fun onStart() {
        super.onStart()
        visible = true
        authenticationListener = {
            if (authentication.busy || authentication.server == null) render() else load()
        }
        authentication.listener = authenticationListener
        if (authentication.server == null) {
            authentication.restore()
        } else if (state.mode == "workflow" && state.data != null) {
            render()
        } else {
            load()
        }
    }

    override fun onStop() {
        visible = false
        busy = false
        generation += 1
        if (authentication.listener === authenticationListener) authentication.listener = null
        authenticationListener = null
        handler.removeCallbacksAndMessages(null)
        super.onStop()
    }

    @Deprecated("The platform callback is required for the API-26 native activity")
    override fun onBackPressed() {
        if (state.mode == "list") {
            super.onBackPressed()
        } else {
            state.mode = "list"
            state.data = null
            state.values.clear()
            state.launch = null
            load()
        }
    }

    private fun request(action: String): JSONObject = JSONObject().put("action", action).put("id", state.id)

    private fun load() {
        if (authentication.busy || authentication.server == null) {
            render()
            return
        }
        generation += 1
        busy = false
        error = null
        render()
        val request =
            when (state.mode) {
                "workflow" -> request("workflow")
                "execution" -> request("execution")
                "approval" -> request("approval")
                else -> JSONObject().put("action", state.section).put("page", state.page)
            }
        call(request) {
            state.data = it
            render()
            if (state.mode == "execution") follow()
        }
    }

    private fun call(
        request: JSONObject,
        success: (JSONObject) -> Unit,
    ) {
        val epoch = generation
        busy = request.optString("action") != "watch"
        if (busy && ::content.isInitialized) {
            for (index in 0 until content.childCount) (content.getChildAt(index) as? Button)?.isEnabled = false
        }
        authentication.native(request, current = { visible && epoch == generation }) { result ->
            if (!visible || epoch != generation) return@native
            busy = false
            result.fold(onSuccess = {
                error = null
                success(it)
            }, onFailure = {
                error = it.message ?: "Atlas could not complete the request."
                val failure = it as? AuthFailure
                if (failure?.kind in setOf("unauthorized", "forbidden", "not_found")) state.data = null
                if (failure?.kind in setOf("invalid_input", "revision_changed")) state.launch = null
                render()
                if (state.mode == "execution" && failure?.kind !in setOf("unauthorized", "forbidden", "not_found")) {
                    handler.postDelayed({ if (visible && epoch == generation) load() }, 3000)
                }
            })
        }
    }

    private fun follow() {
        val data = state.data ?: return
        if (!visible || state.mode != "execution" || data.optString("status") in terminal) return
        call(request("watch").put("after_sequence", data.optLong("sequence"))) { next ->
            if (next.optLong("sequence") >= (state.data?.optLong("sequence") ?: 0)) state.data = next
            render()
            follow()
        }
    }

    private fun open(
        mode: String,
        id: String,
    ) {
        state.mode = mode
        state.id = id
        state.data = null
        state.values.clear()
        state.launch = null
        load()
    }

    private fun render() {
        if (state.session != authentication.sessionGeneration || authentication.server == null) {
            state = State().apply { session = authentication.sessionGeneration }
        }
        val offset = if (::scroll.isInitialized) scroll.scrollY else 0
        content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val padding = (20 * resources.displayMetrics.density).toInt()
                setPadding(padding, padding, padding, padding)
            }
        scroll =
            ScrollView(this).apply {
                setOnApplyWindowInsetsListener { view, insets ->
                    view.setPadding(
                        insets.systemWindowInsetLeft,
                        insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight,
                        insets.systemWindowInsetBottom,
                    )
                    insets
                }
                addView(content, ViewGroup.LayoutParams(-1, -2))
            }
        title = "Automation"
        if (authentication.server == null) {
            text("Sign in to Atlas to use Automation.")
            button("Back to workspace") { finish() }
        } else {
            if (state.mode != "list") button("Back") { onBackPressed() }
            when (state.mode) {
                "workflow" -> workflow()
                "execution" -> execution()
                "approval" -> approval()
                else -> listing()
            }
            error?.let { text(it) }
            button("Refresh") { load() }
        }
        setContentView(scroll)
        scroll.post { scroll.scrollTo(0, offset) }
    }

    private fun listing() {
        listOf("workflows" to "Workflows", "executions" to "Activity", "approvals" to "Approvals").forEach { (value, label) ->
            button(label) {
                state.section = value
                state.page = 1
                state.data = null
                load()
            }
        }
        val epoch = generation
        authentication.pendingLaunch { pending ->
            if (visible && epoch == generation && state.mode == "list" && pending != null) {
                text("Your last launch is unconfirmed. Retry the same request safely.")
                button("Retry pending launch") {
                    call(pending) { open("execution", it.getString("id")) }
                }
            }
        }
        val data = state.data ?: return
        val items = data.optJSONArray("items") ?: JSONArray()
        if (items.length() == 0) text("Nothing here yet.")
        for (index in 0 until items.length()) {
            val item = items.getJSONObject(index)
            val label = if (state.section == "approvals") "Review ${item.optString("step_id")}" else item.optString("name")
            button(label) {
                val mode =
                    when (state.section) {
                        "workflows" -> "workflow"
                        "approvals" -> "approval"
                        else -> "execution"
                    }
                open(mode, item.getString("id"))
            }
            text(item.optString(if (state.section == "workflows") "description" else "status").replace('_', ' '))
        }
        val total = data.optJSONObject("page")?.optInt("total", 1) ?: 1
        if (state.page > 1) {
            button("Previous page") {
                state.page -= 1
                load()
            }
        }
        if (state.page < total) {
            button("Next page") {
                state.page += 1
                load()
            }
        }
    }

    private fun workflow() {
        val data = state.data ?: return
        text(data.optString("name"), 24f)
        text(data.optString("description"))
        text("Version ${data.optInt("version")}")
        val form = data.optJSONObject("form")
        if (form?.optBoolean("supported") != true) {
            text("This contract needs controls that are not supported on mobile yet. Open Atlas on the web to run it.")
            button("Open workflow on web") {
                val base = AtlasCore().sections().first { it.screen == "automation" }.url
                val origin = android.net.Uri.parse(authentication.server ?: return@button)
                val uri =
                    android.net.Uri
                        .parse(base)
                        .buildUpon()
                        .appendPath(state.id)
                        .scheme(origin.scheme)
                        .encodedAuthority(origin.encodedAuthority)
                        .build()
                startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, uri))
            }
            return
        }
        val fields = form.optJSONArray("fields") ?: JSONArray()
        for (index in 0 until fields.length()) field(fields.getJSONObject(index))
        if (fields.length() == 0) text("This workflow requires no inputs.")
        if (data.optBoolean("can_run")) {
            button(if (state.launch == null) "Review and run" else "Retry this launch") { review(fields, data) }
        } else {
            text("You have read-only access to workflows.")
        }
    }

    private fun field(field: JSONObject) {
        val key = field.getJSONArray("path").toString()
        val kind = field.getString("kind")
        val label = field.getString("title") + if (field.optBoolean("required")) " *" else ""
        val initial =
            if (field.has("default")) {
                field.get("default").toString()
            } else if (kind == "boolean" &&
                field.optBoolean("required")
            ) {
                "false"
            } else {
                ""
            }
        val value = state.values.getOrPut(key) { initial }
        text(label)
        when (kind) {
            "boolean", "enum" -> {
                val values = mutableListOf("")
                if (kind == "boolean") {
                    values.addAll(listOf("true", "false"))
                } else {
                    field.optJSONArray("options")?.let { options ->
                        for (index in 0 until options.length()) values.add(options.getString(index))
                    }
                }
                val labels = values.map { if (it.isEmpty()) "Not provided" else it }
                content.addView(
                    Spinner(this).apply {
                        adapter = ArrayAdapter(this@AtlasAutomationActivity, android.R.layout.simple_spinner_dropdown_item, labels)
                        setSelection(values.indexOf(value).coerceAtLeast(0))
                        isEnabled = state.launch == null
                        onItemSelectedListener =
                            object : AdapterView.OnItemSelectedListener {
                                override fun onNothingSelected(parent: AdapterView<*>?) = Unit

                                override fun onItemSelected(
                                    parent: AdapterView<*>?,
                                    view: View?,
                                    position: Int,
                                    id: Long,
                                ) {
                                    state.values[key] =
                                        values[position]
                                }
                            }
                    },
                )
            }
            "date" -> {
                button(value.ifEmpty { "Choose date" }, enabled = state.launch == null) {
                    val today = Calendar.getInstance()
                    DatePickerDialog(this, { _, year, month, day ->
                        state.values[key] = "%04d-%02d-%02d".format(java.util.Locale.ROOT, year, month + 1, day)
                        render()
                    }, today.get(Calendar.YEAR), today.get(Calendar.MONTH), today.get(Calendar.DAY_OF_MONTH)).show()
                }
                if (!field.optBoolean("required")) {
                    button("Omit date", enabled = state.launch == null) {
                        state.values[key] = ""
                        render()
                    }
                }
            }
            else ->
                content.addView(
                    EditText(this).apply {
                        setText(value)
                        contentDescription = label
                        isEnabled = state.launch == null
                        inputType =
                            when (kind) {
                                "integer" -> InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_SIGNED
                                "number" ->
                                    InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_SIGNED or
                                        InputType.TYPE_NUMBER_FLAG_DECIMAL
                                "text" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
                                else -> InputType.TYPE_CLASS_TEXT
                            }
                        addTextChangedListener(
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
                                ) = Unit

                                override fun afterTextChanged(value: Editable?) {
                                    state.values[key] = value.toString()
                                }
                            },
                        )
                    },
                )
        }
        val details = mutableListOf(field.optString("description"))
        for ((key, label) in listOf(
            "minimum" to "Minimum",
            "maximum" to "Maximum",
            "min_length" to "Minimum characters",
            "max_length" to "Maximum characters",
        )) {
            if (field.has(key)) details.add("$label: ${field.get(key)}")
        }
        details
            .filter { it.isNotEmpty() }
            .joinToString(". ")
            .takeIf { it.isNotEmpty() }
            ?.let { text(it) }
    }

    private fun review(
        fields: JSONArray,
        workflow: JSONObject,
    ) {
        try {
            val pending =
                state.launch ?: request("run")
                    .put("revision_id", workflow.getString("revision_id"))
                    .put("request_id", UUID.randomUUID().toString())
                    .put("input", input(fields))
            AlertDialog
                .Builder(this)
                .setTitle("Review launch")
                .setMessage(
                    "Version ${workflow.optInt(
                        "version",
                    )}\n\n${pending.getJSONObject("input").toString(2)}\n\nApproval steps still require their assigned reviewer.",
                ).setNegativeButton("Back", null)
                .setPositiveButton("Run") { _, _ ->
                    state.launch = pending
                    render()
                    call(pending) { open("execution", it.getString("id")) }
                }.show()
        } catch (_: Exception) {
            error = "Check all required fields and numeric values."
            render()
        }
    }

    private fun input(fields: JSONArray): JSONObject {
        val result = JSONObject()
        for (index in 0 until fields.length()) {
            val field = fields.getJSONObject(index)
            val path = field.getJSONArray("path")
            val value = state.values[path.toString()] ?: ""
            var parent = result
            for (part in 0 until path.length() - 1) {
                val key = path.getString(part)
                if (!parent.has(key)) parent.put(key, JSONObject())
                parent = parent.getJSONObject(key)
            }
            if (value.isEmpty() && !field.optBoolean("required")) continue
            check(value.isNotEmpty() || field.getString("kind") in setOf("string", "text"))
            val parsed: Any =
                when (field.getString("kind")) {
                    "boolean" -> value == "true"
                    "integer" -> value.toLong()
                    "number" ->
                        BigDecimal(
                            value.replace(
                                java.text.DecimalFormatSymbols
                                    .getInstance()
                                    .decimalSeparator,
                                '.',
                            ),
                        )
                    else -> value
                }
            parent.put(path.getString(path.length() - 1), parsed)
        }
        return result
    }

    private fun execution() {
        val data = state.data ?: return
        text(data.optString("name"), 24f)
        text(data.optString("status").replace('_', ' '), 20f)
        if (!data.isNull("elapsed_ms")) text("Elapsed: ${data.getLong("elapsed_ms") / 1000}s")
        button("Open execution on web") {
            val uri =
                android.net.Uri
                    .parse(authentication.server ?: return@button)
                    .buildUpon()
                    .encodedPath(data.getString("web_path"))
                    .build()
            startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, uri))
        }
        val steps = data.optJSONArray("steps") ?: JSONArray()
        text("Completed steps: ${data.optInt("cursor")} of ${steps.length()}")
        if (data.optString("status") ==
            "waiting_approval"
        ) {
            text("No processing is happening while this execution awaits its assigned reviewer.")
        }
        for (index in 0 until steps.length()) {
            val step = steps.getJSONObject(index)
            text("${step.optString("step_id")} · ${step.optString("status").replace('_', ' ')}")
        }
        if (data.optString("status") in terminal) {
            button("Load protected results") {
                call(request("result")) { result ->
                    AlertDialog
                        .Builder(this)
                        .setTitle("Execution results")
                        .setMessage(result.getString("outputs_json"))
                        .setPositiveButton("Close", null)
                        .show()
                }
            }
        }
        if (data.optBoolean("can_control")) {
            if (data.optString("status") == "failed") {
                button("Retry from committed progress") { control("retry") }
            } else if (data.optString("status") !in terminal) {
                button("Cancel execution") { control("cancel") }
            }
        }
    }

    private fun control(command: String) {
        generation += 1
        call(request("control").put("command", command)) {
            state.data = it
            render()
            follow()
        }
    }

    private fun approval() {
        val data = state.data ?: return
        text("Exact request", 24f)
        text("Your decision applies to this persisted payload, not an editable replacement.")
        text(data.optString("payload_json", "Unavailable"))
        if (data.optString("status") != "pending" || !data.optBoolean("can_decide")) {
            text(if (data.optString("status") == "pending") "Read-only access." else "This request has already been resolved.")
            return
        }
        listOf("approved" to "Approve", "rejected" to "Reject").forEach { (decision, label) ->
            button(label) {
                AlertDialog
                    .Builder(this)
                    .setTitle("$label this exact request?")
                    .setNegativeButton("Back", null)
                    .setPositiveButton(label) { _, _ ->
                        call(request("decide").put("decision", decision).put("payload_digest", data.getString("payload_digest"))) {
                            open("execution", it.getString("id"))
                        }
                    }.show()
            }
        }
    }

    private fun text(
        value: String,
        size: Float = 16f,
    ) {
        content.addView(
            TextView(this).apply {
                text = value
                textSize = size
                setPadding(0, 12, 0, 12)
            },
        )
    }

    private fun button(
        label: String,
        enabled: Boolean = true,
        action: () -> Unit,
    ) {
        content.addView(
            Button(this).apply {
                text = label
                isEnabled = !busy && enabled
                setOnClickListener { action() }
            },
        )
    }
}
