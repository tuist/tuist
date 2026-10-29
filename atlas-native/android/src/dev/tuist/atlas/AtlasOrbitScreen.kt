package dev.tuist.atlas

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.Editable
import android.text.InputType
import android.text.SpannableString
import android.text.Spanned
import android.text.TextUtils
import android.text.TextWatcher
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.InputMethodManager
import android.widget.BaseAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SearchView
import android.widget.TextView
import android.widget.Toolbar
import org.json.JSONObject
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

class AtlasOrbitScreen(
    private val activity: Activity,
    private val title: String,
    private val model: AtlasOrbitModel,
    private val presence: AtlasPresenceModel?,
    private val navigationChanged: () -> Unit,
    private val appearance: AtlasAppearance? = null,
    private val pickAttachment: (() -> Unit)? = null,
    private val environmentRequest: ((JSONObject, (Result<JSONObject>) -> Unit) -> Unit)? = null,
) {
    val toolbar = Toolbar(activity)
    private val liveStatus =
        TextView(activity).apply {
            textSize = 14f
            visibility = View.GONE
            setPadding(dp(20), dp(6), dp(20), dp(6))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
    private val content =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(16))
        }
    private val scroll =
        ScrollView(activity).apply {
            isFillViewport = true
            addView(content)
        }
    private val composerField =
        EditText(activity).apply {
            hint = "Message"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            maxLines = 6
            minHeight = dp(48)
            isSaveEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
        }
    private val sendButton =
        Button(activity).apply {
            text = "Send"
            isAllCaps = false
            minHeight = dp(48)
            minWidth = dp(64)
        }
    private val attachmentRows = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val attachButton =
        Button(activity).apply {
            text = "Attach"
            contentDescription = "Attach a photo or file, up to 5 MiB"
            isAllCaps = false
            minHeight = dp(48)
            setOnClickListener { pickAttachment?.invoke() }
        }
    private val composer =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(4), dp(16), dp(8))
            addView(attachmentRows, LinearLayout.LayoutParams(-1, -2))
            addView(
                LinearLayout(activity).apply {
                    gravity = Gravity.BOTTOM
                    addView(attachButton, LinearLayout.LayoutParams(-2, -2))
                    addView(composerField, LinearLayout.LayoutParams(0, -2, 1f))
                    addView(sendButton, LinearLayout.LayoutParams(-2, -2))
                },
                LinearLayout.LayoutParams(-1, -2),
            )
        }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            isFocusableInTouchMode = true
            isSaveEnabled = false
            isSaveFromParentEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            addView(toolbar, LinearLayout.LayoutParams(-1, -2))
            addView(liveStatus, LinearLayout.LayoutParams(-1, -2))
            addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(composer, LinearLayout.LayoutParams(-1, -2))
        }
    private var closed = false
    private var syncing = false
    private var composerFor: String? = null
    private var createButton: Button? = null
    private var renderedThread: String? = null
    private var firstMessage: String? = null
    private var lastMessage: String? = null
    private val messageViews = mutableMapOf<String, View>()
    private var scrollRevision = 0L
    private var promptJumpPending = false
    private var promptDialog: AlertDialog? = null
    private var promptThread: String? = null
    private var promptEntries = emptyList<AtlasOrbitPromptIndex.Entry>()
    private var promptAdapter: BaseAdapter? = null
    private val formatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT).withZone(ZoneId.systemDefault())
    private var renderedContent: Any? = null
    private var listMenuReady = false
    private var searchItem: MenuItem? = null
    private var domainItem: MenuItem? = null
    private var statusItem: MenuItem? = null
    private var composeItem: MenuItem? = null
    private var searchTask: Runnable? = null
    private var syncingSearch = false
    private val search =
        SearchView(activity).apply {
            queryHint = "Search titles and summaries"
            isSaveEnabled = false
            isSaveFromParentEnabled = false
            minimumHeight = dp(48)
        }
    private val listener: () -> Unit = { render() }
    private val presenceListener: () -> Unit = { if (model.createDraft != null) render() }

    init {
        model.listener = listener
        presence?.listener = presenceListener
        search.setOnQueryTextListener(
            object : SearchView.OnQueryTextListener {
                override fun onQueryTextChange(value: String?): Boolean {
                    if (syncingSearch) return true
                    searchTask?.let(search::removeCallbacks)
                    searchTask = Runnable { if (!closed && model.selectionId == null) model.filter(query = value.orEmpty()) }
                    search.postDelayed(searchTask, 300)
                    return true
                }

                override fun onQueryTextSubmit(value: String?): Boolean {
                    searchTask?.let(search::removeCallbacks)
                    model.filter(query = value.orEmpty())
                    hideKeyboard()
                    return true
                }
            },
        )
        composerField.addTextChangedListener(
            object : TextWatcher {
                override fun beforeTextChanged(
                    value: CharSequence?,
                    start: Int,
                    count: Int,
                    after: Int,
                ) = Unit

                override fun onTextChanged(
                    value: CharSequence?,
                    start: Int,
                    before: Int,
                    count: Int,
                ) = Unit

                override fun afterTextChanged(value: Editable?) {
                    if (syncing) return
                    composerFor?.let { model.setDraft(it, value?.toString().orEmpty()) }
                    sendButton.isEnabled =
                        (value?.isNotBlank() == true || model.snapshot.draftAttachments.isNotEmpty()) && !model.sending &&
                        !model.attachmentBusy && !model.snapshot.uploadPending && !model.snapshot.needsSession
                }
            },
        )
        sendButton.setOnClickListener {
            composerFor?.let {
                scroll.scrollTo(0, content.height)
                model.send(it, composerField.text.toString())
            }
        }
        render()
    }

    fun load() {
        if (model.selectionId == null && !model.snapshot.loading) model.load()
    }

    fun close() {
        closed = true
        searchTask?.let(search::removeCallbacks)
        promptDialog?.dismiss()
        environmentDialog?.dismiss()
        messageViews.clear()
        AtlasOrbitAttachments.clear()
        hideKeyboard()
        if (model.listener === listener) model.listener = null
        if (presence?.listener === presenceListener) presence.listener = null
    }

    fun back(): Boolean {
        if (model.selectionId == null && searchItem?.isActionViewExpanded == true) {
            searchItem?.collapseActionView()
            return true
        }
        val draft = model.createDraft
        if (draft != null && !model.snapshot.saving && !model.snapshot.loading &&
            (draft.title.isNotBlank() || draft.participants.isNotEmpty())
        ) {
            AlertDialog
                .Builder(activity)
                .setTitle("Discard this thread?")
                .setPositiveButton("Discard") { _, _ -> model.discardCreate() }
                .setNegativeButton("Keep editing", null)
                .show()
            return true
        }
        hideKeyboard()
        return model.back()
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()

    private fun render() {
        if (closed) return
        if (promptThread != protectedThreadId()) promptDialog?.dismiss()
        if (environmentThread != protectedThreadId()) environmentDialog?.dismiss()
        updatePromptIndex()
        if (model.createDraft != null || model.selecting || model.selectionId != null || !listMenuReady) {
            listMenuReady = false
            searchTask?.let(search::removeCallbacks)
            toolbar.menu.clear()
        }
        when {
            model.createDraft != null -> renderCreate()
            model.selecting -> renderSelection()
            model.selectionId != null && model.snapshot.selected?.id != model.selectionId -> renderSelection()
            model.snapshot.selected != null -> renderThread()
            else -> renderList()
        }
        if (model.createDraft != null || model.selecting || model.snapshot.selected?.id != model.selectionId || model.selectionId == null) {
            messageViews.clear()
        }
        navigationChanged()
    }

    private fun renderSelection() {
        composerFor = null
        composer.visibility = View.GONE
        liveStatus.visibility = View.GONE
        toolbar.title = title
        toolbar.subtitle = null
        refreshAction { model.refresh() }
        renderedContent = null
        content.removeAllViews()
        errors()
        if (model.snapshot.historyLoading || (model.snapshot.error == null && model.failure == null)) {
            text("Loading thread…")
        } else {
            button("Retry") { model.refresh() }
        }
    }

    private fun renderList() {
        val snapshot = model.snapshot
        renderedThread = null
        composerFor = null
        composer.visibility = View.GONE
        liveStatus.visibility = View.GONE
        toolbar.title = title
        val domainTitle =
            if (snapshot.domainFilter == "unclassified") {
                "Unclassified"
            } else {
                snapshot.assistant
                    ?.domains
                    ?.firstOrNull { it.id == snapshot.domainFilter }
                    ?.name ?: "All domains"
            }
        toolbar.subtitle = "${snapshot.statusFilter.replaceFirstChar(Char::uppercase)} · $domainTitle"
        if (!listMenuReady) configureListMenu()
        searchItem?.isEnabled = snapshot.assistant?.searchable == true && !snapshot.cached
        domainItem?.isEnabled = snapshot.assistant?.searchable == true && !snapshot.cached
        statusItem?.title = if (snapshot.statusFilter == "active") "Show archived" else "Show active"
        composeItem?.isEnabled = snapshot.assistant != null && !snapshot.cached && !snapshot.loading
        val key =
            listOf(
                "list",
                snapshot.assistant,
                snapshot.threads,
                snapshot.loading,
                snapshot.hasMore,
                snapshot.cached,
                snapshot.statusFilter,
                snapshot.query,
                snapshot.domainFilter,
                snapshot.error,
                model.failure,
            )
        if (key == renderedContent) return
        renderedContent = key
        content.removeAllViews()
        if (snapshot.cached && (snapshot.error != null || model.failure != null)) {
            content.addView(
                LinearLayout(activity).apply {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(
                        TextView(activity).apply {
                            text = "Couldn’t refresh"
                            textSize = 15f
                        },
                        LinearLayout.LayoutParams(0, -2, 1f),
                    )
                    addView(
                        Button(activity, null, android.R.attr.borderlessButtonStyle).apply {
                            text = "Retry"
                            isAllCaps = false
                            minWidth = dp(64)
                            minHeight = dp(48)
                            isEnabled = !snapshot.loading
                            setOnClickListener { model.refresh() }
                        },
                        LinearLayout.LayoutParams(-2, -2),
                    )
                },
                LinearLayout.LayoutParams(-1, -2),
            )
        } else {
            errors()
        }
        for (priority in listOf("now", "today", "later")) {
            val threads = snapshot.threads.filter { it.priority == priority }
            for (thread in threads) {
                conversationRow(thread)
            }
        }
        if (snapshot.threads.any { it.priority != null } && snapshot.threads.any { it.priority == null }) heading("Conversations")
        for (thread in snapshot.threads.filter { it.priority == null }) {
            conversationRow(thread)
        }
        if (snapshot.threads.isEmpty() && !snapshot.loading && snapshot.error == null) {
            text(
                if (snapshot.query.isNotEmpty() ||
                    snapshot.domainFilter.isNotEmpty()
                ) {
                    "No matching conversations. Try another search or choose All domains."
                } else if (snapshot.statusFilter ==
                    "archived"
                ) {
                    "No archived conversations."
                } else {
                    "No conversations yet. Start one using New conversation."
                },
            )
        }
        if (snapshot.loading && snapshot.threads.isEmpty()) text("Loading threads…")
        if (!snapshot.loading && snapshot.hasMore) button("Load more threads") { model.loadMore() }
    }

    private fun errors() {
        listOfNotNull(model.failure, model.snapshot.error).distinct().forEach { text(it) }
    }

    private fun configureListMenu() {
        listMenuReady = true
        refreshAction { model.refresh() }
        searchItem =
            toolbar.menu.add("Search conversations").apply {
                setIcon(android.R.drawable.ic_menu_search)
                actionView = search
                setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS or MenuItem.SHOW_AS_ACTION_COLLAPSE_ACTION_VIEW)
                setOnActionExpandListener(
                    object : MenuItem.OnActionExpandListener {
                        override fun onMenuItemActionExpand(item: MenuItem) = true

                        override fun onMenuItemActionCollapse(item: MenuItem): Boolean {
                            if (!listMenuReady) return true
                            searchTask?.let(search::removeCallbacks)
                            syncingSearch = true
                            search.setQuery("", false)
                            syncingSearch = false
                            model.filter(query = "")
                            return true
                        }
                    },
                )
            }
        syncingSearch = true
        search.setQuery(model.snapshot.query, false)
        syncingSearch = false
        if (model.snapshot.query.isNotEmpty()) searchItem?.expandActionView()
        domainItem =
            toolbar.menu.add("Filter by domain").apply {
                setIcon(android.R.drawable.ic_menu_sort_by_size)
                setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                setOnMenuItemClickListener {
                    showDomainFilter()
                    true
                }
            }
        composeItem =
            toolbar.menu.add("New conversation").apply {
                setIcon(android.R.drawable.ic_menu_edit)
                setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                setOnMenuItemClickListener {
                    model.newPrivate()
                    true
                }
            }
        statusItem =
            toolbar.menu.add("Show archived").setOnMenuItemClickListener {
                model.filterStatus(if (model.snapshot.statusFilter == "active") "archived" else "active")
                true
            }
        menuAction("New shared thread") { model.startCreate() }
    }

    private fun showDomainFilter() {
        val domains =
            listOf(AtlasOrbitModel.Domain("", "All domains")) +
                model.snapshot.assistant
                    ?.domains
                    .orEmpty() +
                AtlasOrbitModel.Domain("unclassified", "Unclassified")
        AlertDialog
            .Builder(activity)
            .setTitle("Filter by domain")
            .setSingleChoiceItems(
                domains
                    .map {
                        it.name
                    }.toTypedArray(),
                domains.indexOfFirst { it.id == model.snapshot.domainFilter },
            ) { dialog, index ->
                model.filter(domain = domains[index].id)
                dialog.dismiss()
            }.setNegativeButton("Cancel", null)
            .show()
    }

    private var environmentDialog: AlertDialog? = null
    private var environmentThread: String? = null

    private fun showEnvironments(id: String) {
        val request = environmentRequest ?: return
        environmentDialog?.dismiss()
        environmentThread = id
        val rows =
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(20), dp(8), dp(20), dp(8))
            }
        val dialog =
            AlertDialog
                .Builder(activity)
                .setTitle("Tool environment")
                .setView(ScrollView(activity).apply { addView(rows) })
                .setNegativeButton("Close", null)
                .create()
        environmentDialog = dialog

        fun current() = !closed && protectedThreadId() == id && environmentDialog === dialog && dialog.isShowing

        fun message(value: String) {
            rows.addView(
                TextView(activity).apply {
                    text = value
                    textSize = 16f
                },
            )
        }

        fun select(action: JSONObject) {
            if (!current()) return
            rows.removeAllViews()
            message("Updating environment…")
            request(action.put("thread_id", id)) { result ->
                if (!current()) return@request
                rows.removeAllViews()
                result.fold({
                    message("Environment updated. Hosted environments may take a moment to start. Reopen to refresh.")
                }, { message("Couldn’t update the environment. Reopen to refresh before trying again.") })
            }
        }

        fun option(
            label: String,
            action: JSONObject,
        ) {
            rows.addView(
                Button(activity).apply {
                    text = label
                    isAllCaps = false
                    minHeight = dp(48)
                    setOnClickListener { select(action) }
                },
            )
        }
        dialog.show()
        message("Loading environments…")
        request(JSONObject().put("action", "list")) { result ->
            if (!current()) return@request
            rows.removeAllViews()
            result.fold({ overview ->
                message(
                    "Pip stays on Atlas. File and terminal tools run in the selected environment. Selecting Server only stops its hosted environment.",
                )
                option(
                    "Server only",
                    JSONObject()
                        .put("action", "select")
                        .put("environment_id", JSONObject.NULL)
                        .put("project_id", JSONObject.NULL),
                )
                val providers = overview.optJSONArray("providers")
                for (index in 0 until (providers?.length() ?: 0)) {
                    val provider = providers!!.getJSONObject(index)
                    option(
                        "Start ${provider.getString("name")}",
                        JSONObject()
                            .put("action", "start_provider")
                            .put("provider", provider.getString("id")),
                    )
                }
                val environments = overview.getJSONArray("environments")
                for (index in 0 until environments.length()) {
                    val environment = environments.getJSONObject(index)
                    if (environment.optString("provider", "native") != "native") {
                        message("${environment.getString("name")}: ${environment.optString("provider_state", "unavailable")}")
                    } else if (environment.optBoolean("enabled") && environment.optBoolean("online")) {
                        val projects = environment.getJSONArray("projects")
                        for (projectIndex in 0 until projects.length()) {
                            val project = projects.getJSONObject(projectIndex)
                            option(
                                "${environment.getString("name")} · ${project.getString("name")}",
                                JSONObject()
                                    .put("action", "select")
                                    .put("environment_id", environment.getString("id"))
                                    .put("project_id", project.getString("id")),
                            )
                        }
                    }
                }
            }, { message("Couldn’t load environments. Close and reopen to retry.") })
        }
    }

    private fun renderThread() {
        val snapshot = model.snapshot
        val thread = snapshot.selected ?: return
        val id = thread.id
        val assistant = snapshot.assistant
        toolbar.title = if (thread.isPrivate) assistant?.name ?: thread.title else thread.title
        toolbar.subtitle =
            if (thread.isPrivate) "Private" else (listOf(assistant?.name ?: "Pip") + thread.participants.map { it.name }).joinToString(", ")
        refreshAction { model.refresh() }
        if (thread.isPrivate && !thread.archived && environmentRequest != null) {
            menuAction("Tool environment") { showEnvironments(id) }
        }
        if (presence?.selfId != null && thread.ownerId == presence.selfId) {
            menuAction(if (thread.archived) "Restore conversation" else "Archive conversation") {
                if (!thread.isPrivate && !thread.archived) {
                    AlertDialog
                        .Builder(activity)
                        .setTitle("Archive this shared conversation?")
                        .setMessage("It will become read-only for everyone. You can restore it from Archived.")
                        .setNegativeButton("Cancel", null)
                        .setPositiveButton("Archive") { _, _ -> model.archive(thread) }
                        .show()
                } else {
                    model.archive(thread)
                }
            }
        }
        toolbar.menu.add("Prompts").apply {
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            actionView =
                Button(activity, null, android.R.attr.borderlessButtonStyle).apply {
                    text = "Prompts"
                    contentDescription = "Prompts, jump to a loaded message"
                    isAllCaps = false
                    minWidth = dp(48)
                    minHeight = dp(48)
                    isEnabled = protectedThreadId() != null
                    setOnClickListener { showPromptIndex() }
                }
        }
        renderComposer(id, thread)
        renderLive()
        // Viewer and typing snapshots arrive often; only rebuild the history when it changed.
        val key =
            listOf(
                id,
                snapshot.messages,
                snapshot.hasOlder,
                snapshot.historyLoading,
                snapshot.error,
                model.failure,
                model.expandedTools,
                model.expandedToolGroups,
                model.revealedEvidence,
                thread.archived,
            )
        if (key == renderedContent) return
        renderedContent = key
        val atBottom = !scroll.canScrollVertically(1)
        val fromBottom = content.height - scroll.scrollY
        val previousFirst = firstMessage
        val switched = renderedThread != id
        renderedThread = id
        messageViews.clear()
        content.removeAllViews()
        if (snapshot.hasOlder) {
            button(if (snapshot.historyLoading) "Loading earlier messages…" else "Load earlier messages", !snapshot.historyLoading) {
                model.loadOlder()
            }
        }
        if (snapshot.messages.isEmpty()) text(if (snapshot.historyLoading) "Loading messages…" else "No messages yet.")
        for (group in model.timeline()) {
            if (group.size > 1 && group.first().isTool) {
                val id = group.first().id
                val expanded = id in model.expandedToolGroups
                button("${if (expanded) "▾" else "▸"} ${group.size} tool calls") { model.toggleToolGroup(id) }
                if (expanded) group.forEach(::message)
            } else {
                group.forEach(::message)
            }
        }
        errors()
        if (thread.archived) text("This thread is archived. You can read it but not reply.")
        val first = snapshot.messages.firstOrNull()?.id
        val last = snapshot.messages.lastOrNull()?.id
        val prepended = !switched && previousFirst != null && first != previousFirst && last == lastMessage
        val appended = last != lastMessage
        firstMessage = first
        lastMessage = last
        val revision = scrollRevision
        val jumping = promptJumpPending
        scroll.post {
            if (closed || protectedThreadId() != id || revision != scrollRevision || jumping) return@post
            when {
                switched -> scroll.scrollTo(0, content.height)
                prepended -> scroll.scrollTo(0, content.height - fromBottom)
                atBottom && appended -> scroll.scrollTo(0, content.height)
            }
        }
    }

    private fun protectedThreadId() =
        model.snapshot.selected?.id?.takeIf {
            !closed && !model.selecting && model.createDraft == null && !model.snapshot.needsSession && model.selectionId == it
        }

    private fun showPromptIndex() {
        val id = protectedThreadId() ?: return
        if (promptDialog != null) return
        hideKeyboard()
        promptThread = id
        val adapter =
            object : BaseAdapter() {
                override fun getCount() = maxOf(1, promptEntries.size)

                override fun getItem(position: Int) = promptEntries.getOrNull(position)

                override fun getItemId(position: Int) = position.toLong()

                override fun areAllItemsEnabled() = false

                override fun isEnabled(position: Int) = getItem(position) != null

                override fun getView(
                    position: Int,
                    convertView: View?,
                    parent: ViewGroup,
                ): View {
                    val entry = getItem(position)
                    return LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        minimumHeight = dp(48)
                        setPadding(dp(24), dp(10), dp(24), dp(10))
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                        addView(
                            TextView(activity).apply {
                                text =
                                    entry?.preview
                                        ?: if (model.snapshot.historyLoading) "Loading prompts…" else "No prompts in loaded history."
                                textSize = 16f
                                maxLines = 2
                                ellipsize = TextUtils.TruncateAt.END
                                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                            },
                        )
                        if (entry != null) {
                            val author = if (entry.author.isBlank()) "Person" else entry.author
                            val timestamp = entry.timestamp?.let { runCatching { formatter.format(it) }.getOrDefault("") }.orEmpty()
                            addView(
                                TextView(activity).apply {
                                    text = "$author · ${entry.relativeTime}"
                                    textSize = 14f
                                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                                },
                            )
                            contentDescription =
                                "Jump to prompt. ${entry.preview}. $author. ${entry.relativeTime}. $timestamp"
                        } else {
                            contentDescription = (getChildAt(0) as TextView).text
                        }
                    }
                }
            }
        promptAdapter = adapter
        val dialog =
            AlertDialog
                .Builder(activity)
                .setTitle("Prompts · newest first")
                .setAdapter(adapter) { _, position ->
                    promptEntries.getOrNull(position)?.let { jumpToPrompt(id, it.id) }
                }.setNeutralButton("Load earlier", null)
                .setNegativeButton("Close", null)
                .create()
        promptDialog = dialog
        dialog.setOnDismissListener {
            if (promptDialog === dialog) {
                promptDialog = null
                promptThread = null
                promptAdapter = null
                promptEntries = emptyList()
            }
        }
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                if (protectedThreadId() == id && model.snapshot.hasOlder && !model.snapshot.historyLoading) model.loadOlder()
            }
            updatePromptIndex()
        }
        dialog.show()
    }

    private fun updatePromptIndex() {
        val dialog = promptDialog ?: return
        promptEntries = AtlasOrbitPromptIndex.entries(model.snapshot.messages)
        promptAdapter?.notifyDataSetChanged()
        dialog.getButton(AlertDialog.BUTTON_NEUTRAL)?.apply {
            visibility = if (model.snapshot.hasOlder) View.VISIBLE else View.GONE
            isEnabled = !model.snapshot.historyLoading
            text = if (model.snapshot.historyLoading) "Loading earlier…" else "Load earlier"
            minHeight = dp(48)
        }
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE)?.minHeight = dp(48)
    }

    private fun jumpToPrompt(
        threadId: String,
        messageId: String,
    ) {
        if (protectedThreadId() != threadId) return
        val revision = ++scrollRevision
        promptJumpPending = true
        scroll.post {
            if (revision != scrollRevision) return@post
            promptJumpPending = false
            if (protectedThreadId() != threadId || renderedThread != threadId) return@post
            val target = messageViews[messageId] ?: return@post
            val bounds = Rect()
            target.getDrawingRect(bounds)
            scroll.offsetDescendantRectToMyCoords(target, bounds)
            scroll.smoothScrollTo(0, (bounds.top - scroll.paddingTop).coerceAtLeast(0))
            scroll.announceForAccessibility("Jumped to prompt")
        }
    }

    private fun renderComposer(
        id: String,
        thread: AtlasOrbitModel.Thread,
    ) {
        val snapshot = model.snapshot
        composer.visibility = if (thread.archived) View.GONE else View.VISIBLE
        if (thread.archived) return
        syncing = true
        // Rust owns the draft: entering a thread restores it, and sending clears it. Echoes of writes still
        // in flight are older than what is on screen, so they never replace the person's typing.
        if (composerFor != id || (model.draftsInFlight == 0 && composerField.text.toString() != snapshot.draft)) {
            composerFor = id
            composerField.setText(snapshot.draft)
            composerField.setSelection(composerField.text.length)
        }
        syncing = false
        sendButton.text = if (model.sending) "Sending…" else "Send"
        val enabled = !model.sending && !model.attachmentBusy && !snapshot.needsSession
        composerField.isEnabled = !snapshot.needsSession
        sendButton.isEnabled =
            enabled && !snapshot.uploadPending && (composerField.text.isNotBlank() || snapshot.draftAttachments.isNotEmpty())
        attachButton.isEnabled = enabled && !snapshot.uploadPending && snapshot.draftAttachments.size < 4 && pickAttachment != null
        attachmentRows.removeAllViews()
        for (attachment in snapshot.draftAttachments) {
            attachmentRows.addView(
                Button(activity).apply {
                    text = "Remove ${attachment.filename} · ${attachment.byteSize} bytes ×"
                    contentDescription = "Remove attachment ${attachment.filename}"
                    isAllCaps = false
                    minHeight = dp(48)
                    isEnabled = enabled
                    setOnClickListener { model.removeAttachment(attachment.id) }
                },
            )
        }
        if (model.attachmentBusy || snapshot.uploadPending) {
            attachmentRows.addView(
                TextView(activity).apply {
                    text =
                        if (model.attachmentBusy) {
                            "Preparing attachment…"
                        } else {
                            "Upload not confirmed: ${snapshot.uploadFilename.orEmpty()}"
                        }
                    accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
                },
            )
            if (!model.attachmentBusy && snapshot.uploadPending) {
                attachmentRows.addView(
                    Button(activity).apply {
                        text = "Retry upload"
                        isAllCaps = false
                        minHeight = dp(48)
                        setOnClickListener { model.retryUpload() }
                    },
                )
                attachmentRows.addView(
                    Button(activity).apply {
                        text = "Discard upload"
                        isAllCaps = false
                        minHeight = dp(48)
                        setOnClickListener { model.discardUpload() }
                    },
                )
            }
        }
    }

    private fun renderLive() {
        val snapshot = model.snapshot
        if (closed || snapshot.selected == null || model.createDraft != null) {
            liveStatus.visibility = View.GONE
            return
        }
        val self = presence?.selfId
        val others = snapshot.people.filter { it.id != self }
        val typing = others.filter { it.typing }.map { it.name }
        val lines =
            buildList {
                snapshot.liveMessage?.let { add(it) }
                if (others.isNotEmpty()) add("Viewing: ${others.joinToString(", ") { it.name }}")
                when (typing.size) {
                    0 -> Unit
                    1 -> add("${typing.single()} is typing…")
                    else -> add("${typing.joinToString(", ")} are typing…")
                }
            }
        liveStatus.text = lines.joinToString("\n")
        liveStatus.visibility = if (lines.isEmpty()) View.GONE else View.VISIBLE
    }

    private fun renderCreate() {
        val draft = model.createDraft ?: return
        // Rust reports creation through `loading` while it creates and selects the new thread.
        val saving = model.snapshot.saving || model.snapshot.loading
        renderedContent = null
        renderedThread = null
        composerFor = null
        composer.visibility = View.GONE
        liveStatus.visibility = View.GONE
        toolbar.title = "New shared thread"
        toolbar.subtitle = null
        val focused = content.findFocus() as? EditText
        createButton = null
        content.removeAllViews()
        heading("Title")
        val field =
            EditText(activity).apply {
                hint = "What is this thread about?"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                minHeight = dp(48)
                isSaveEnabled = false
                importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
                setText(draft.title)
                setSelection(text.length)
                isEnabled = !saving
                addTextChangedListener(
                    object : TextWatcher {
                        override fun beforeTextChanged(
                            value: CharSequence?,
                            start: Int,
                            count: Int,
                            after: Int,
                        ) = Unit

                        override fun onTextChanged(
                            value: CharSequence?,
                            start: Int,
                            before: Int,
                            count: Int,
                        ) = Unit

                        override fun afterTextChanged(value: Editable?) {
                            model.setCreateTitle(value?.toString().orEmpty())
                            createButton?.isEnabled = !model.snapshot.saving && !model.snapshot.loading && value?.isNotBlank() == true
                        }
                    },
                )
            }
        content.addView(field, LinearLayout.LayoutParams(-1, -2))
        if (focused != null) field.requestFocus()
        heading("Participants")
        text("You are included automatically. People come from your Atlas team.")
        val self = presence?.selfId
        val people = presence?.people.orEmpty().filter { it.id != self }
        if (people.isEmpty()) text(presence?.error ?: "Loading people…")
        for (person in people) {
            content.addView(
                CheckBox(activity).apply {
                    text = person.name
                    minHeight = dp(48)
                    isSaveEnabled = false
                    isChecked = person.id in draft.participants
                    isEnabled = !saving
                    setOnClickListener { model.toggleParticipant(person.id) }
                },
                LinearLayout.LayoutParams(-1, -2),
            )
        }
        errors()
        createButton =
            button(if (saving) "Creating…" else "Create thread", !saving && draft.title.isNotBlank()) {
                hideKeyboard()
                model.create()
            }
        button("Cancel", !saving) { back() }
    }

    private fun message(
        value: AtlasOrbitModel.Message,
        host: LinearLayout = content,
    ) {
        val self = presence?.selfId
        val author =
            when {
                value.authorId != null && value.authorId == self -> "You"
                else -> value.authorName
            }
        val card =
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(if (host === content) 0 else dp(12), dp(8), 0, dp(8))
            }
        messageViews[value.id] = card
        if (value.kind == "system") {
            if (value.noticeKind == "private_handoff" || value.noticeKind == "handoff") {
                card.setPadding(dp(16), dp(16), dp(16), dp(16))
                val recapTitle = if (value.noticeKind == "private_handoff") "Your catch-up · Only visible to you" else "Conversation recap"
                card.addView(
                    body(recapTitle).apply {
                        setTypeface(typeface, Typeface.BOLD)
                        if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
                        setCompoundDrawablesRelativeWithIntrinsicBounds(android.R.drawable.ic_lock_lock, 0, 0, 0)
                        compoundDrawablePadding = dp(8)
                    },
                )
                card.background =
                    android.graphics.drawable.GradientDrawable().apply {
                        val color = android.util.TypedValue()
                        activity.theme.resolveAttribute(android.R.attr.colorBackground, color, true)
                        setColor(appearance?.palette?.optString("surface")?.let(android.graphics.Color::parseColor) ?: color.data)
                        cornerRadius = dp(12).toFloat()
                    }
            }
            card.addView(
                body(value.body).apply {
                    if (value.noticeKind == "joined") {
                        gravity = Gravity.CENTER
                        textSize = 14f
                    }
                },
            )
            host.addView(card, LinearLayout.LayoutParams(-1, -2))
            return
        }
        if (value.isTool) {
            val children = model.childTools(value.id)
            val expanded = value.id in model.expandedTools
            val status = value.toolStatus?.replaceFirstChar(Char::uppercase).orEmpty()
            val name = value.toolName ?: "Tool"
            card.addView(
                Button(activity, null, android.R.attr.borderlessButtonStyle).apply {
                    text =
                        "${if (expanded) "▾" else "▸"} $name${if (status.isEmpty()) "" else " · $status"}${if (children.isEmpty()) "" else " · ${children.size} child calls"}"
                    isAllCaps = false
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    minHeight = dp(48)
                    contentDescription = "Tool $name, $status, ${if (expanded) "expanded" else "collapsed"}"
                    setOnClickListener { model.toggleTool(value.id) }
                },
                LinearLayout.LayoutParams(-1, -2),
            )
            if (expanded) {
                if (value.body.isNotEmpty()) card.addView(body(value.body))
                value.component?.let { component ->
                    card.addView(
                        AtlasThreadCardView(
                            activity,
                            JSONObject(component),
                            appearance,
                        ) { event -> model.componentAction(value.id, event) },
                        LinearLayout.LayoutParams(-1, dp(180)),
                    )
                }
                if (value.component == null || value.id in model.revealedEvidence) {
                    if (value.toolInput.isNotEmpty()) card.addView(body("Input\n${value.toolInput}", true))
                    if (value.toolOutput.isNotEmpty()) card.addView(body("Output\n${value.toolOutput}", true))
                }
                children.forEach { message(it, card) }
            }
            host.addView(card, LinearLayout.LayoutParams(-1, -2))
            return
        }
        val header =
            listOf(author, time(value.insertedAt)).filter { it.isNotEmpty() }.joinToString(" · ")
        card.addView(
            TextView(activity).apply {
                text =
                    SpannableString(header).apply {
                        if (author.isNotEmpty()) setSpan(StyleSpan(Typeface.BOLD), 0, author.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                textSize = 14f
            },
        )
        card.addView(body(value.body))
        for (attachment in value.attachments) {
            card.addView(
                Button(activity).apply {
                    text =
                        "${if (attachment.contentType.startsWith(
                                "image/",
                            )
                        ) {
                            "Image"
                        } else {
                            "File"
                        }}: ${attachment.filename} · ${attachment.byteSize} bytes"
                    isAllCaps = false
                    minHeight = dp(48)
                    setOnClickListener { openAttachment(attachment) }
                },
            )
        }
        host.addView(card, LinearLayout.LayoutParams(-1, -2))
    }

    private fun openAttachment(attachment: AtlasOrbitModel.Attachment) {
        val id = model.snapshot.selected?.id ?: return
        val epoch = model.attachmentEpoch()
        model.downloadAttachment(attachment.id) { result ->
            if (closed || !model.canOpenAttachment(id, epoch)) return@downloadAttachment
            val value = result.getOrNull()
            if (value == null) {
                AlertDialog
                    .Builder(
                        activity,
                    ).setMessage("Could not download this attachment. Refresh the thread and try again.")
                    .setPositiveButton("OK", null)
                    .show()
                return@downloadAttachment
            }
            AtlasOrbitAttachments.cache(activity.applicationContext, value) { cached ->
                val uri = cached.getOrNull()
                if (closed || !model.canOpenAttachment(id, epoch)) {
                    uri?.let(AtlasOrbitAttachments::remove)
                    return@cache
                }
                if (uri == null) {
                    AlertDialog
                        .Builder(activity)
                        .setMessage("Could not open this attachment.")
                        .setPositiveButton("OK", null)
                        .show()
                    return@cache
                }
                try {
                    activity.startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, attachment.contentType)
                            .apply { clipData = ClipData.newRawUri("Attachment", uri) }
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                    )
                } catch (_: ActivityNotFoundException) {
                    AtlasOrbitAttachments.remove(uri)
                    AlertDialog
                        .Builder(
                            activity,
                        ).setMessage("No app on this device can open this file type.")
                        .setPositiveButton("OK", null)
                        .show()
                }
            }
        }
    }

    private fun body(
        value: String,
        monospace: Boolean = false,
    ) = TextView(activity).apply {
        text = value
        textSize = if (monospace) 13f else 16f
        if (monospace) typeface = Typeface.MONOSPACE
        setTextIsSelectable(true)
        setPadding(0, dp(4), 0, dp(4))
    }

    private fun time(value: String) = runCatching { formatter.format(Instant.parse(value)) }.getOrDefault("")

    private fun refreshAction(action: () -> Unit) {
        menuAction("Refresh", action)
    }

    private fun menuAction(
        label: String,
        action: () -> Unit,
    ) {
        toolbar.menu.add(label).setOnMenuItemClickListener {
            action()
            true
        }
    }

    private fun heading(value: String) {
        content.addView(
            TextView(activity).apply {
                text = value
                textSize = 20f
                setPadding(0, dp(20), 0, dp(8))
                if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
            },
        )
    }

    private fun text(value: String) {
        content.addView(
            TextView(activity).apply {
                text = value
                textSize = 15f
                setPadding(0, dp(8), 0, dp(8))
            },
        )
    }

    private fun button(
        label: String,
        enabled: Boolean = true,
        action: () -> Unit,
    ): Button {
        val button =
            Button(activity).apply {
                text = label
                setTag(R.id.atlas_primary_action, true)
                isAllCaps = false
                minHeight = dp(48)
                isEnabled = enabled
                setOnClickListener { action() }
            }
        content.addView(button, ViewGroup.LayoutParams(-1, -2))
        return button
    }

    private fun row(
        title: String,
        description: String,
        enabled: Boolean = true,
        accessibility: String? = null,
        action: () -> Unit,
    ) {
        val label =
            SpannableString(if (description.isEmpty()) title else "$title\n$description").apply {
                setSpan(StyleSpan(Typeface.BOLD), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        val background = activity.obtainStyledAttributes(intArrayOf(android.R.attr.selectableItemBackground))
        val resource = background.getResourceId(0, 0)
        background.recycle()
        content.addView(
            Button(activity).apply {
                text = label
                textSize = 16f
                isAllCaps = false
                isEnabled = enabled
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                minHeight = dp(if (description.isEmpty()) 48 else 64)
                setPadding(dp(12), dp(12), dp(12), dp(12))
                setBackgroundResource(resource)
                accessibility?.let { contentDescription = "$it. $description" }
                setOnClickListener {
                    hideKeyboard()
                    action()
                }
            },
            ViewGroup.LayoutParams(-1, -2),
        )
    }

    private fun conversationRow(thread: AtlasOrbitModel.Thread) {
        val background =
            activity.obtainStyledAttributes(
                intArrayOf(android.R.attr.selectableItemBackground, android.R.attr.textColorSecondary),
            )
        val ripple = background.getResourceId(0, 0)
        val secondaryColor = background.getColor(1, 0)
        background.recycle()
        val largeText = activity.resources.configuration.fontScale >= 1.5f
        val row =
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                minimumHeight = dp(64)
                setPadding(dp(4), dp(8), dp(4), dp(8))
                isEnabled = !model.snapshot.loading || model.snapshot.cached
                isFocusable = true
                contentDescription =
                    listOfNotNull(
                        thread.priorityTitle,
                        model.snapshot.assistant
                            ?.domains
                            ?.firstOrNull { it.id == thread.domain }
                            ?.name,
                        thread.title,
                        thread.summary,
                        time(thread.updatedAt),
                        if (thread.isPrivate) "Private conversation" else "Shared conversation",
                        thread.activityLabel,
                    ).filter { it.isNotEmpty() }.joinToString(". ")
                setBackgroundResource(ripple)
                accessibilityDelegate =
                    object : View.AccessibilityDelegate() {
                        override fun onInitializeAccessibilityNodeInfo(
                            host: View,
                            info: AccessibilityNodeInfo,
                        ) {
                            super.onInitializeAccessibilityNodeInfo(host, info)
                            info.className = Button::class.java.name
                        }
                    }
                setOnClickListener {
                    hideKeyboard()
                    model.select(thread.id)
                }
            }
        row.addView(
            TextView(activity).apply {
                text = thread.title
                textSize = 17f
                maxLines = if (largeText) 3 else 1
                ellipsize = TextUtils.TruncateAt.END
                setTypeface(null, Typeface.BOLD)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            },
            LinearLayout.LayoutParams(-1, -2),
        )
        if (thread.summary.isNotEmpty()) {
            row.addView(
                TextView(activity).apply {
                    id = android.R.id.text2
                    text = thread.summary
                    textSize = 15f
                    maxLines = if (largeText) 3 else 1
                    ellipsize = TextUtils.TruncateAt.END
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                },
                LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(2) },
            )
        }
        val domain =
            model.snapshot.assistant
                ?.domains
                ?.firstOrNull { it.id == thread.domain }
                ?.name
        row.addView(
            LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                thread.priorityTitle?.let { priority ->
                    addView(
                        TextView(activity).apply {
                            id = android.R.id.text2
                            text = priority
                            textSize = 12f
                            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                        },
                        LinearLayout.LayoutParams(-2, -2).apply { marginEnd = dp(8) },
                    )
                }
                if (domain != null) {
                    addView(
                        TextView(activity).apply {
                            id = android.R.id.text2
                            text = domain
                            textSize = 12f
                            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                            setPadding(dp(6), dp(2), dp(6), dp(2))
                            this.background =
                                GradientDrawable().apply {
                                    cornerRadius = dp(5).toFloat()
                                    setStroke(dp(1), (secondaryColor and 0x00FFFFFF) or 0x33000000)
                                }
                        },
                    )
                }
                addView(View(activity), LinearLayout.LayoutParams(0, 0, 1f))
                if (!largeText) {
                    addView(
                        TextView(activity).apply {
                            id = android.R.id.text2
                            text = time(thread.updatedAt)
                            textSize = 12f
                            setPadding(dp(8), 0, 0, 0)
                        },
                    )
                }
                addView(
                    AtlasOrbitRunningIndicator(activity).apply {
                        visibility = if (thread.activityLabel != null) View.VISIBLE else View.INVISIBLE
                    },
                    LinearLayout.LayoutParams(dp(8), dp(8)).apply { marginStart = dp(8) },
                )
            },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) },
        )
        if (largeText) {
            row.addView(
                TextView(activity).apply {
                    id = android.R.id.text2
                    text = time(thread.updatedAt)
                    textSize = 12f
                    setPadding(0, dp(4), 0, 0)
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                },
            )
        }
        content.addView(row, ViewGroup.LayoutParams(-1, -2))
    }

    private fun hideKeyboard() {
        val focus = view.findFocus() ?: return
        focus.clearFocus()
        view.requestFocus()
        (activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(focus.windowToken, 0)
    }
}

private class AtlasOrbitRunningIndicator(
    context: Context,
) : View(context) {
    private var pulse: ObjectAnimator? = null

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        val colors = context.obtainStyledAttributes(intArrayOf(android.R.attr.colorAccent))
        background =
            GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(colors.getColor(0, 0))
            }
        colors.recycle()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updatePulse()
    }

    override fun onVisibilityChanged(
        changedView: View,
        visibility: Int,
    ) {
        super.onVisibilityChanged(changedView, visibility)
        updatePulse()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        updatePulse()
    }

    override fun onDetachedFromWindow() {
        pulse?.cancel()
        pulse = null
        super.onDetachedFromWindow()
    }

    private fun updatePulse() {
        if (isAttachedToWindow && isShown && windowVisibility == VISIBLE && ValueAnimator.areAnimatorsEnabled()) {
            if (pulse != null) return
            pulse =
                ObjectAnimator.ofFloat(this, ALPHA, 1f, 0.4f).apply {
                    duration = 800
                    repeatCount = ValueAnimator.INFINITE
                    repeatMode = ValueAnimator.REVERSE
                    start()
                }
        } else {
            pulse?.cancel()
            pulse = null
            alpha = 1f
        }
    }
}

internal object AtlasOrbitPromptIndex {
    data class Entry(
        val id: String,
        val preview: String,
        val author: String,
        val timestamp: Instant?,
        val relativeTime: String,
    )

    fun entries(
        messages: List<AtlasOrbitModel.Message>,
        now: Instant = Instant.now(),
    ): List<Entry> =
        messages.asReversed().filter { it.kind == "human" }.map { message ->
            val text =
                message.body
                    .ifBlank { message.attachments.joinToString(", ") { it.filename } }
                    .replace(Regex("\\s+"), " ")
                    .trim()
                    .ifBlank { "Empty prompt" }
            val preview = if (text.codePointCount(0, text.length) > 160) text.substring(0, text.offsetByCodePoints(0, 160)) + "…" else text
            val timestamp = runCatching { Instant.parse(message.insertedAt) }.getOrNull()
            val seconds = timestamp?.let { Duration.between(it, now).seconds.coerceAtLeast(0) }
            val relative =
                when {
                    seconds == null -> "Time unavailable"
                    seconds < 60 -> "Just now"
                    seconds < 3600 -> ago(seconds / 60, "minute")
                    seconds < 86400 -> ago(seconds / 3600, "hour")
                    else -> ago(seconds / 86400, "day")
                }
            Entry(message.id, preview, message.authorName, timestamp, relative)
        }

    private fun ago(
        value: Long,
        unit: String,
    ) = "$value $unit${if (value == 1L) "" else "s"} ago"
}
