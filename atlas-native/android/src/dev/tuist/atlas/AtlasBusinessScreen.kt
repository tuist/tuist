package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.Dialog
import android.app.TimePickerDialog
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SearchView
import android.widget.TextView
import android.widget.Toolbar
import java.math.BigDecimal
import java.math.MathContext
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.FutureTask
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class AtlasBusinessScreen(
    private val activity: Activity,
    private val title: String,
    private val model: AtlasBusinessModel,
    private val navigationChanged: () -> Unit = {},
    private val presence: AtlasPresenceModel? = null,
    private val logoLoader: (String, (Bitmap?) -> Unit) -> (() -> Unit) = AccountLogos::load,
) {
    val toolbar = Toolbar(activity)
    private val alsoHere =
        TextView(activity).apply {
            visibility = View.GONE
            textSize = 14f
            setPadding(dp(20), dp(8), dp(20), dp(8))
        }
    private val search =
        SearchView(activity).apply {
            queryHint = "Search $title"
            isIconifiedByDefault = false
            isSaveEnabled = false
            isSaveFromParentEnabled = false
            setQuery(model.query, false)
        }
    private val content =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(24))
            isSaveEnabled = false
            isSaveFromParentEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
    private val scroll = ScrollView(activity).apply { addView(content) }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            isFocusableInTouchMode = true
            isSaveEnabled = false
            isSaveFromParentEnabled = false
            addView(toolbar, LinearLayout.LayoutParams(-1, -2))
            addView(alsoHere, LinearLayout.LayoutParams(-1, -2))
            addView(search, LinearLayout.LayoutParams(-1, -2))
            addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
            setOnApplyWindowInsetsListener { root, insets ->
                root.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
                scroll.setPadding(0, 0, 0, insets.systemWindowInsetBottom)
                insets
            }
            requestFocus()
        }
    private var closed = false
    private var dialog: Dialog? = null
    private var previousDraft: AtlasBusinessModel.Draft? = null
    private var previousSelection: String? = null
    private var rendering = false
    private var renderGeneration = 0
    private var restoreScrollY: Int? = null
    private var pageEnd: View? = null
    private val logoCancellations = mutableListOf<() -> Unit>()
    private val pendingLogos = mutableListOf<() -> Boolean>()
    private val listener: () -> Unit = { render() }
    private val presenceListener: () -> Unit = { renderPresence() }
    private val layoutListener =
        android.view.ViewTreeObserver.OnGlobalLayoutListener {
            restoreScrollY?.let {
                scroll.scrollTo(0, it)
                restoreScrollY = null
                rendering = false
            }
            loadVisibleLogos()
            val identity = renderGeneration
            scroll.post { if (identity == renderGeneration) loadNearEnd() }
        }

    init {
        model.listener = listener
        presence?.listener = presenceListener
        search.setOnQueryTextListener(
            object : SearchView.OnQueryTextListener {
                override fun onQueryTextChange(value: String?) = true

                override fun onQueryTextSubmit(value: String?): Boolean {
                    hideKeyboard()
                    model.load(search = value.orEmpty())
                    return true
                }
            },
        )
        search.setOnCloseListener {
            model.load(search = "")
            false
        }
        scroll.setOnScrollChangeListener { _, _, y, _, _ ->
            if (!rendering) loadVisibleLogos()
            if (!rendering && model.selected == null && model.draft == null) {
                model.rememberScroll(y)
                loadNearEnd()
            }
        }
        content.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
        render()
    }

    fun load() {
        if (!model.loaded) model.load()
    }

    fun back(): Boolean {
        hideKeyboard()
        if (model.draft != null && !model.saving) {
            dialog =
                AlertDialog
                    .Builder(activity)
                    .setTitle("Discard changes?")
                    .setMessage("Your unsaved changes will be lost.")
                    .setPositiveButton("Discard") { _, _ -> model.back() }
                    .setNegativeButton("Keep editing", null)
                    .show()
            return true
        }
        return model.back()
    }

    fun close() {
        closed = true
        dialog?.dismiss()
        logoCancellations.forEach { it() }
        logoCancellations.clear()
        pendingLogos.clear()
        if (content.viewTreeObserver.isAlive) content.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
        if (model.listener === listener) model.listener = null
        if (presence?.listener === presenceListener) presence.listener = null
    }

    private fun renderPresence() {
        if (closed) return
        val names =
            presence
                ?.people
                ?.filter { it.here }
                ?.joinToString(", ") { it.name }
                .orEmpty()
        alsoHere.text = if (names.isEmpty()) "" else "Also here: $names"
        alsoHere.visibility = if (names.isEmpty()) View.GONE else View.VISIBLE
    }

    private fun render() {
        if (closed) return
        rendering = true
        renderGeneration += 1
        val draft = model.draft
        val selected = model.selected
        presence?.show(model.resource, selected?.id ?: draft?.id)
        renderPresence()
        val changedDestination = previousDraft !== draft || previousSelection != selected?.id
        restoreScrollY =
            if (draft == null && selected == null) {
                model.listScrollY
            } else if (changedDestination) {
                0
            } else {
                scroll.scrollY
            }
        previousDraft = draft
        previousSelection = selected?.id
        toolbar.title =
            if (draft != null) {
                if (draft.id == null) "New ${singular()}" else "Edit ${singular()}"
            } else {
                title
            }
        search.visibility = if (draft == null && selected == null) View.VISIBLE else View.GONE
        search.isEnabled = true
        if (!model.busy && model.query.isEmpty() && search.query.isNotEmpty() && !search.hasFocus()) search.setQuery("", false)
        toolbar.menu.clear()
        if (draft == null && selected == null) {
            toolbar.menu.add("Filters").apply {
                setShowAsAction(android.view.MenuItem.SHOW_AS_ACTION_ALWAYS)
                setOnMenuItemClickListener {
                    filters()
                    true
                }
            }
        }
        logoCancellations.forEach { it() }
        logoCancellations.clear()
        pendingLogos.clear()
        pageEnd = null
        content.removeAllViews()
        model.notice?.let { text(it) }
        model.error?.let {
            text(if (model.notice != null) "${model.notice} Refresh failed: $it" else it)
            if (draft == null) {
                button("Retry refresh") {
                    if (selected != null && model.notice == null) model.show(selected) else model.load()
                }
            }
        }
        if (model.busy && !model.loadingMore) text(if (model.saving) "Saving… Please wait." else "Loading…")
        when {
            draft != null -> editor(draft)
            selected != null -> detail(selected)
            else -> list()
        }
        navigationChanged()
    }

    private fun list() {
        if (model.filters.isNotEmpty()) {
            text("Active filters: " + model.filters.entries.joinToString(" · ") { "${label(it.key)}: ${filterName(it.key, it.value)}" })
            button("Reset filters", true) { model.load(filters = emptyMap()) }
        }
        if (model.resource == "invoices") {
            text("Invoices", true)
            text("Manual invoice bookkeeping. Imported invoices are read-only.")
        }
        if (model.canWrite) button("New ${singular()}") { model.edit() }
        button("Refresh", true) {
            hideKeyboard()
            model.load()
        }
        if (model.loaded) {
            text(if (model.query.isEmpty()) "${model.total} records" else "${model.total} results for “${model.query}”")
            if (!model.canWrite) text("Read-only access. Atlas controls permission to create and change records.")
            if (model.items.isEmpty() && !model.busy) text("No matching records.")
        } else if (!model.busy && model.error != null) {
            text("This destination remains available. Check your access with your Atlas administrator, or retry.")
        }
        var previousGroup: String? = null
        model.items.forEach { value ->
            if (model.resource == "tasks" && model.filters["group_by"] == "reminder") {
                val group = value["reminder_group"]
                if (group != previousGroup) text(reminderGroup(group), true)
                previousGroup = group
            }
            val subtitle =
                when (model.resource) {
                    "tasks" ->
                        listOf(
                            value["status"],
                            value["assignee_name"],
                            value["due_on"].takeIf(String::isNotEmpty)?.let { "Due $it" },
                            value["remind_at"].takeIf(String::isNotEmpty)?.let {
                                "${if (value["reminder_group"] == "overdue") "Overdue reminder" else "Reminder"}: ${display(
                                    "remind_at",
                                    it,
                                )}"
                            },
                        )
                    "accounts" -> listOf(value["primary_domain"], value["segment"], value["deal_stage"])
                    else ->
                        listOf(
                            value["invoice_number"],
                            value["status"],
                            "${value["total_amount_value"]} ${value["total_amount_currency"]}",
                            if (value.canEdit) "Manual" else "Read-only",
                        )
                }.filterNotNull().filter(String::isNotBlank).joinToString(" · ")
            val rowLabel = "${recordTitle(value)}\n$subtitle"
            if (model.resource == "accounts") {
                accountRow(value, rowLabel) {
                    hideKeyboard()
                    model.show(value)
                }
            } else {
                button(rowLabel, enabled = !model.saving, row = true) {
                    hideKeyboard()
                    model.show(value)
                }
            }
        }
        pageEnd =
            text(
                if (model.loadingMore) {
                    "Loading more…"
                } else if (model.loaded) {
                    "${model.items.size} of ${model.total} records"
                } else {
                    ""
                },
            )
        model.nextPageError?.let {
            text("Could not load more records: $it")
            button("Retry loading more", !model.busy) { model.retryNextPage() }
        }
        if (model.resource == "invoices" && model.summary.isNotEmpty()) {
            text("Monthly invoice totals", true)
            text("All invoices, not just this page or search. Each currency is shown separately. This is not cash flow.")
            model.summary.groupBy { it.currency }.toSortedMap().forEach { (currency, months) ->
                text(currency, true)
                val sorted = months.sortedBy { it.month }
                content.addView(
                    HorizontalScrollView(activity).apply {
                        addView(AtlasInvoiceChart(activity, sorted), ViewGroup.LayoutParams(-2, dp(208)))
                    },
                    ViewGroup.LayoutParams(-1, -2),
                )
                sorted.forEach { text("${it.month}: ${it.amount.toPlainString()} $currency") }
            }
        }
    }

    private fun detail(value: AtlasBusinessModel.Record) {
        if (model.resource == "accounts") content.addView(accountLogo(value))
        text(recordTitle(value), true)
        if (!value.canEdit) text("Read-only record")
        val fields =
            when (model.resource) {
                "tasks" -> listOf("title", "description", "status", "assignee_name", "account_name", "due_on", "remind_at")
                else -> model.editableFields
            }
        fields.forEach { key -> text("${label(key)}\n${display(key, value[key]).ifEmpty { "Not set" }}") }
        if (value.canEdit) button("Edit ${singular()}") { model.edit(value) }
        if (model.resource == "tasks" && value.canEdit && value["status"] != "completed") {
            button("Complete task") { model.complete(value) }
        }
        if (value.canDelete) {
            button("Delete ${singular()}") {
                dialog =
                    AlertDialog
                        .Builder(activity)
                        .setTitle("Delete ${singular()}?")
                        .setMessage("${recordTitle(value)} will be permanently deleted.")
                        .setPositiveButton("Delete") { _, _ -> model.delete(value) }
                        .setNegativeButton("Cancel", null)
                        .show()
            }
        }
        button("Back to $title", !model.saving) { back() }
    }

    private fun editor(draft: AtlasBusinessModel.Draft) {
        text("${if (draft.id == null) "New" else "Edit"} ${singular()}", true)
        if (model.resource == "tasks") text("A blank assignee on a new task assigns it to you. Reminder times use your device time zone.")
        if (model.resource == "invoices") text("Only manually entered invoices can be edited. Enter an ISO currency code, for example EUR.")
        model.editableFields.forEach { key ->
            when {
                key in listOf("due_on", "due_date", "invoice_date", "next_renewal_date", "remind_at") -> dateField(key, draft)
                choicesKey(key) != null -> choiceField(key, draft)
                else -> input(key, draft.fields[key].orEmpty())
            }
        }
        button("Save ${singular()}") {
            hideKeyboard()
            model.save()
        }
        button("Discard changes", !model.saving) { back() }
    }

    private fun choicesKey(key: String): String? =
        when (key) {
            "assignee_id" -> "users"
            "account_id" -> "accounts"
            "segment" -> "segments"
            "status" -> "statuses"
            "deal_stage" -> "deal_stages"
            else -> null
        }

    private fun loadNearEnd() {
        val end = pageEnd ?: return
        if (!closed && !rendering && end.isLaidOut && scroll.height > 0 &&
            end.top <= scroll.scrollY + scroll.height + dp(160)
        ) {
            model.loadMore()
        }
    }

    private fun filters() {
        val keys = model.filterKeys
        val rows = keys.map { key -> "${label(key)}: ${model.filters[key]?.let { filterName(key, it) } ?: "All"}" } + "Reset filters"
        dialog =
            AlertDialog
                .Builder(activity)
                .setTitle("Filter $title")
                .setItems(rows.toTypedArray()) { _, index ->
                    if (closed) return@setItems
                    if (index == keys.size) model.load(filters = emptyMap()) else filter(keys[index])
                }.setNegativeButton("Cancel", null)
                .show()
    }

    private fun filterChoices(key: String): List<AtlasBusinessModel.Choice> {
        val values =
            when {
                key == "group_by" -> listOf("reminder")
                key == "reminder" -> listOf("overdue", "upcoming", "none")
                key == "status" && model.resource == "tasks" -> listOf("open", "completed")
                else -> return model.options[choicesKey(key)].orEmpty()
            }
        return values.map { AtlasBusinessModel.Choice(it, if (key == "reminder") reminderGroup(it) else label(it)) }
    }

    private fun filterName(
        key: String,
        value: String,
    ) = filterChoices(key).firstOrNull { it.id == value }?.name ?: value

    private fun filter(key: String) {
        val rows = listOf(AtlasBusinessModel.Choice("", if (key == "group_by") "No grouping" else "All")) + filterChoices(key)
        val current = model.filters[key].orEmpty()
        dialog =
            AlertDialog
                .Builder(activity)
                .setTitle(label(key))
                .setSingleChoiceItems(rows.map { it.name }.toTypedArray(), rows.indexOfFirst { it.id == current }) { picker, index ->
                    if (!closed) model.load(filters = model.filters + (key to rows[index].id))
                    picker.dismiss()
                }.setNegativeButton("Cancel", null)
                .show()
    }

    private fun reminderGroup(value: String) =
        when (value) {
            "overdue" -> "Overdue reminders"
            "upcoming" -> "Upcoming reminders"
            "none" -> "No reminder"
            "completed" -> "Completed"
            else -> "Other reminders"
        }

    private fun accountRow(
        value: AtlasBusinessModel.Record,
        label: String,
        action: () -> Unit,
    ) {
        content.addView(
            LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = dp(72)
                setPadding(dp(12), dp(16), dp(12), dp(16))
                contentDescription = label
                isFocusable = true
                val background = activity.obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackground))
                setBackgroundResource(background.getResourceId(0, 0))
                background.recycle()
                addView(accountLogo(value))
                addView(
                    TextView(activity).apply {
                        text = label
                        textSize = 16f
                        setPadding(dp(12), 0, 0, 0)
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                    },
                    LinearLayout.LayoutParams(0, -2, 1f),
                )
                setOnClickListener { action() }
            },
            ViewGroup.LayoutParams(-1, -2),
        )
    }

    private fun accountLogo(value: AtlasBusinessModel.Record): View {
        val identity = renderGeneration
        val frame =
            object : FrameLayout(activity) {
                private val clip = Path()

                override fun draw(canvas: Canvas) {
                    val saved = canvas.save()
                    clip.reset()
                    clip.addRoundRect(0f, 0f, width.toFloat(), height.toFloat(), dp(10).toFloat(), dp(10).toFloat(), Path.Direction.CW)
                    canvas.clipPath(clip)
                    super.draw(canvas)
                    canvas.restoreToCount(saved)
                }
            }.apply {
                layoutParams = ViewGroup.LayoutParams(dp(44), dp(44))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                clipToOutline = true
                outlineProvider =
                    object : ViewOutlineProvider() {
                        override fun getOutline(
                            view: View,
                            outline: Outline,
                        ) {
                            outline.setRoundRect(0, 0, view.width, view.height, dp(10).toFloat())
                        }
                    }
            }
        val colors = activity.obtainStyledAttributes(intArrayOf(android.R.attr.colorControlHighlight))
        frame.setBackgroundColor(colors.getColor(0, 0x22303030))
        colors.recycle()
        frame.addView(
            TextView(activity).apply {
                text = recordTitle(value).trim().take(1).uppercase()
                textSize = 22f
                gravity = Gravity.CENTER
            },
            FrameLayout.LayoutParams(-1, -1),
        )
        val domain = value["primary_domain"].trim()
        if (domain.isNotEmpty()) {
            pendingLogos += {
                if (!frame.getGlobalVisibleRect(android.graphics.Rect())) {
                    false
                } else {
                    logoCancellations +=
                        logoLoader(domain) { bitmap ->
                            if (!closed && identity == renderGeneration && bitmap != null) {
                                frame.addView(
                                    ImageView(activity).apply {
                                        setImageBitmap(bitmap)
                                        scaleType = ImageView.ScaleType.FIT_CENTER
                                    },
                                    FrameLayout.LayoutParams(-1, -1),
                                )
                            }
                        }
                    true
                }
            }
        }
        return frame
    }

    private fun loadVisibleLogos() {
        if (!closed) pendingLogos.removeAll { it() }
    }

    private fun choiceField(
        key: String,
        draft: AtlasBusinessModel.Draft,
    ) {
        val choices = model.options[choicesKey(key)].orEmpty()
        val current = draft.fields[key].orEmpty()
        val name = choices.firstOrNull { it.id == current }?.name ?: current.ifEmpty { "Not set" }
        button("${label(key)}: $name") {
            val rows = listOf(AtlasBusinessModel.Choice("", "Not set")) + choices
            dialog =
                AlertDialog
                    .Builder(activity)
                    .setTitle(label(key))
                    .setSingleChoiceItems(rows.map { it.name }.toTypedArray(), rows.indexOfFirst { it.id == current }) { picker, index ->
                        if (!closed && model.draft === draft && !model.saving) {
                            model.field(key, rows[index].id)
                            render()
                        }
                        picker.dismiss()
                    }.setNegativeButton("Cancel", null)
                    .show()
        }
    }

    private fun input(
        key: String,
        value: String,
    ) {
        val label = text(label(key))
        val field =
            EditText(activity).apply {
                id = View.generateViewId()
                isSaveEnabled = false
                isSaveFromParentEnabled = false
                importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
                minHeight = dp(48)
                isEnabled = !model.saving
                inputType =
                    when (key) {
                        "description" ->
                            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                        "current_value", "total_amount_value" ->
                            InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL or
                                InputType.TYPE_NUMBER_FLAG_SIGNED
                        "url", "primary_domain" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
                        else -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                    }
                if (key == "description") minLines = 3
                setText(value)
                addTextChangedListener(
                    object : TextWatcher {
                        override fun beforeTextChanged(
                            s: CharSequence?,
                            start: Int,
                            count: Int,
                            after: Int,
                        ) {}

                        override fun onTextChanged(
                            s: CharSequence?,
                            start: Int,
                            before: Int,
                            count: Int,
                        ) {
                            model.field(key, s.toString())
                        }

                        override fun afterTextChanged(s: Editable?) {}
                    },
                )
            }
        label.labelFor = field.id
        content.addView(field, ViewGroup.LayoutParams(-1, -2))
    }

    private fun dateField(
        key: String,
        draft: AtlasBusinessModel.Draft,
    ) {
        val value = draft.fields[key].orEmpty()
        button("${label(key)}: ${display(key, value).ifEmpty { "Not set" }}") {
            hideKeyboard()
            val instant = runCatching { Instant.parse(value).atZone(ZoneId.systemDefault()) }.getOrNull()
            val date = if (key == "remind_at") instant?.toLocalDate() else runCatching { LocalDate.parse(value) }.getOrNull()
            val initial = date ?: LocalDate.now()

            fun set(value: String) {
                if (closed || model.draft !== draft || model.saving) return
                model.field(key, value)
                render()
            }
            dialog =
                DatePickerDialog(activity, { _, year, month, day ->
                    val chosen = LocalDate.of(year, month + 1, day)
                    if (key == "remind_at") {
                        val time = instant?.toLocalTime() ?: LocalTime.of(9, 0)
                        dialog =
                            TimePickerDialog(
                                activity,
                                { _, hour, minute ->
                                    set(
                                        chosen
                                            .atTime(hour, minute)
                                            .atZone(ZoneId.systemDefault())
                                            .toInstant()
                                            .toString(),
                                    )
                                },
                                time.hour,
                                time.minute,
                                android.text.format.DateFormat
                                    .is24HourFormat(activity),
                            ).also { it.show() }
                    } else {
                        set(chosen.toString())
                    }
                }, initial.year, initial.monthValue - 1, initial.dayOfMonth).also { it.show() }
        }
        if (value.isNotEmpty()) {
            button("Clear ${label(key).lowercase()}") {
                model.field(key, "")
                render()
            }
        }
    }

    private fun display(
        key: String,
        value: String,
    ): String =
        if (key == "remind_at" && value.isNotEmpty()) {
            runCatching {
                DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm z").format(Instant.parse(value).atZone(ZoneId.systemDefault()))
            }.getOrDefault(value)
        } else {
            value
        }

    private fun recordTitle(value: AtlasBusinessModel.Record) =
        value[
            when (model.resource) {
                "tasks" -> "title"
                "accounts" -> "name"
                else -> "vendor_name"
            },
        ].ifBlank { "Untitled ${singular()}" }

    private fun singular() =
        when (model.resource) {
            "tasks" -> "task"
            "accounts" -> "account"
            else -> "invoice"
        }

    private fun label(key: String) =
        when (key) {
            "assignee_id", "assignee_name" -> "Assignee"
            "account_id", "account_name" -> "Account"
            "due_on", "due_date" -> "Due date"
            "remind_at" -> "Reminder"
            "group_by" -> "Group by"
            "total_amount_value" -> "Total amount"
            "total_amount_currency" -> "Currency"
            "url" -> "Website URL"
            else -> key.replace('_', ' ').replaceFirstChar(Char::uppercase)
        }

    private fun text(
        value: String,
        heading: Boolean = false,
    ): TextView =
        TextView(activity).apply {
            text = value
            textSize = if (heading) 22f else 16f
            setPadding(0, dp(12), 0, dp(8))
            if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = heading
            content.addView(this, ViewGroup.LayoutParams(-1, -2))
        }

    private fun button(
        label: String,
        enabled: Boolean = !model.busy,
        row: Boolean = false,
        action: () -> Unit,
    ) {
        content.addView(
            Button(activity).apply {
                text = label
                setTag(R.id.atlas_primary_action, !row)
                isAllCaps = false
                textSize = 16f
                minHeight = dp(if (row) 72 else 48)
                isEnabled = enabled
                if (row) {
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    setPadding(dp(12), dp(16), dp(12), dp(16))
                    val background = activity.obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackground))
                    setBackgroundResource(background.getResourceId(0, 0))
                    background.recycle()
                }
                setOnClickListener { action() }
            },
            ViewGroup.LayoutParams(-1, -2),
        )
    }

    private fun hideKeyboard() {
        activity.currentFocus?.clearFocus()
        view.requestFocus()
        (activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(view.windowToken, 0)
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
}

// Public favicons use a separate credential-free client, never the Atlas auth coordinator.
private object AccountLogos {
    private data class Cached(
        val bitmap: Bitmap?,
        val at: Long = android.os.SystemClock.elapsedRealtime(),
    )

    private val cache = android.util.LruCache<String, Cached>(64)
    private val main = Handler(Looper.getMainLooper())
    private val executor = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS, ArrayBlockingQueue(32))

    fun load(
        domain: String,
        completion: (Bitmap?) -> Unit,
    ): () -> Unit {
        val cached = cache.get(domain)
        if (cached != null && (cached.bitmap != null || android.os.SystemClock.elapsedRealtime() - cached.at < 60_000)) {
            completion(cached.bitmap)
            return {}
        }
        val cancelled =
            java.util.concurrent.atomic
                .AtomicBoolean(false)
        val connection =
            java.util.concurrent.atomic
                .AtomicReference<HttpURLConnection?>()
        val task =
            FutureTask<Unit> {
                val bitmap =
                    runCatching {
                        val encoded = URLEncoder.encode(domain, "UTF-8")
                        val http =
                            URI(
                                "https://www.google.com/s2/favicons?domain=$encoded&sz=128",
                            ).toURL().openConnection() as HttpURLConnection
                        connection.set(http)
                        try {
                            if (cancelled.get()) return@runCatching null
                            val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
                            http.connectTimeout = 3000
                            http.readTimeout = 3000
                            if (http.responseCode != 200) return@runCatching null
                            val data = ByteArray(256 * 1024 + 1)
                            var size = 0
                            http.inputStream.use { stream ->
                                while (size < data.size && !cancelled.get()) {
                                    if (android.os.SystemClock.elapsedRealtime() >= deadline) return@runCatching null
                                    val count = stream.read(data, size, minOf(4096, data.size - size))
                                    if (count < 0) break
                                    size += count
                                }
                            }
                            if (size == data.size || cancelled.get()) return@runCatching null
                            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeByteArray(data, 0, size, bounds)
                            if (bounds.outWidth !in 1..512 || bounds.outHeight !in 1..512) return@runCatching null
                            val decode =
                                BitmapFactory.Options().apply {
                                    inSampleSize = 1
                                    while (maxOf(bounds.outWidth, bounds.outHeight) / inSampleSize > 128) inSampleSize *= 2
                                }
                            BitmapFactory.decodeByteArray(data, 0, size, decode)
                        } finally {
                            http.disconnect()
                            connection.set(null)
                        }
                    }.getOrNull()
                if (!cancelled.get()) {
                    cache.put(domain, Cached(bitmap))
                    main.post { if (!cancelled.get()) completion(bitmap) }
                }
            }
        try {
            executor.execute(task)
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            completion(null)
        }
        return {
            cancelled.set(true)
            task.cancel(true)
            executor.remove(task)
            connection.get()?.disconnect()
        }
    }
}

class AtlasInvoiceChart(
    context: Context,
    private val months: List<AtlasBusinessModel.Month>,
) : View(context) {
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val colors = context.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary, android.R.attr.colorAccent))
    private var foreground = colors.getColor(0, 0xff303030.toInt())
    private var accent = colors.getColor(1, 0xff087caa.toInt())

    init {
        colors.recycle()
        minimumWidth = (maxOf(3, months.size) * 96 * density * maxOf(1f, resources.configuration.fontScale)).toInt()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    fun setTheme(
        foreground: Int,
        accent: Int,
    ) {
        this.foreground = foreground
        this.accent = accent
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val maximum = months.maxOfOrNull { it.amount.abs() }?.max(BigDecimal.ONE) ?: BigDecimal.ONE
        val hasNegative = months.any { it.amount.signum() < 0 }
        val top = 30 * density
        val bottom = height - 42 * density
        val baseline = if (hasNegative) (top + bottom) / 2 else bottom
        val scale = if (hasNegative) (bottom - top) / 2 else bottom - top
        paint.color = foreground
        paint.strokeWidth = density
        canvas.drawLine(8 * density, baseline, width - 8 * density, baseline, paint)
        val cell = width.toFloat() / maxOf(1, months.size)
        months.forEachIndexed { index, month ->
            val center = cell * (index + 0.5f)
            val ratio = month.amount.divide(maximum, MathContext.DECIMAL64).toFloat()
            val end = baseline - ratio * scale
            paint.color = accent
            canvas.drawRect(center - 18 * density, minOf(baseline, end), center + 18 * density, maxOf(baseline, end), paint)
            paint.color = foreground
            paint.textAlign = Paint.Align.CENTER
            paint.textSize = 12 * resources.displayMetrics.scaledDensity
            canvas.drawText(month.month, center, height - 12 * density, paint)
        }
    }
}
