package dev.tuist.atlas

import android.app.Activity
import android.content.Context
import android.graphics.Typeface
import android.text.InputType
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SearchView
import android.widget.TextView
import android.widget.Toolbar

class AtlasWorkspaceScreen(
    private val activity: Activity,
    private val model: AtlasWorkspaceModel,
    private val serverName: String,
    private val selected: (AtlasSection) -> Unit,
    private val navigationChanged: () -> Unit,
    private val notice: String? = null,
) {
    val toolbar = Toolbar(activity)
    private val search =
        SearchView(activity).apply {
            queryHint = "Find a feature"
            isIconifiedByDefault = false
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            isSaveEnabled = false
            isSaveFromParentEnabled = false
        }
    private val content =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(24))
        }
    private val scroll = ScrollView(activity).apply { addView(content) }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            isFocusableInTouchMode = true
            addView(toolbar, LinearLayout.LayoutParams(-1, -2))
            addView(search, LinearLayout.LayoutParams(-1, -2))
            addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
            setOnApplyWindowInsetsListener { root, insets ->
                root.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
                scroll.setPadding(0, 0, 0, insets.systemWindowInsetBottom)
                insets
            }
            requestFocus()
        }
    private var syncing = false
    private val listener: () -> Unit = {
        render()
        scroll.scrollTo(0, 0)
    }

    init {
        model.listener = listener
        search.setOnQueryTextListener(
            object : SearchView.OnQueryTextListener {
                override fun onQueryTextSubmit(query: String?): Boolean {
                    hideKeyboard()
                    return true
                }

                override fun onQueryTextChange(value: String?): Boolean {
                    if (!syncing) model.search(value.orEmpty())
                    return true
                }
            },
        )
        render()
    }

    fun back(): Boolean {
        if (!model.canBack) return false
        hideKeyboard()
        return model.back()
    }

    fun close() {
        if (model.listener === listener) model.listener = null
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()

    private fun heading(value: String) {
        content.addView(
            TextView(activity).apply {
                text = value
                textSize = 20f
                setPadding(dp(12), dp(20), dp(12), dp(12))
                if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
            },
        )
    }

    private fun row(
        title: String,
        description: String,
        icon: Int,
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
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                minHeight = dp(if (description.isEmpty()) 48 else 64)
                setPadding(dp(12), dp(12), dp(12), dp(12))
                setBackgroundResource(resource)
                setCompoundDrawablesRelativeWithIntrinsicBounds(icon, 0, 0, 0)
                compoundDrawablePadding = dp(12)
                setOnClickListener {
                    hideKeyboard()
                    action()
                }
            },
            ViewGroup.LayoutParams(-1, -2),
        )
    }

    private fun destination(
        section: AtlasSection,
        searching: Boolean = false,
    ) {
        val subtitle =
            buildString {
                if (searching) append("${model.breadcrumb(section)}\n")
                append(section.description)
            }
        row(
            section.title,
            subtitle,
            android.R.drawable.ic_menu_agenda,
        ) { selected(section) }
    }

    private fun render() {
        toolbar.title = model.group?.title ?: "Browse"
        toolbar.subtitle = serverName
        if (search.query.toString() != model.query) {
            syncing = true
            search.setQuery(model.query, false)
            syncing = false
        }
        content.removeAllViews()
        if (model.query.isBlank()) {
            model.children().forEach { group ->
                row(group.title, "", android.R.drawable.ic_menu_agenda) {
                    model.open(group.id)
                    scroll.scrollTo(0, 0)
                }
            }
            model.entries().forEach { destination(it) }
        } else {
            heading("Features")
            val matches = model.results()
            if (matches.isEmpty()) heading("No matching features")
            matches.forEach { destination(it, true) }
        }
        notice?.let { heading(it) }
        navigationChanged()
    }

    private fun hideKeyboard() {
        search.clearFocus()
        view.requestFocus()
        (activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(search.windowToken, 0)
    }
}
