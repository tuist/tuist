package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toolbar
import java.time.LocalDate
import java.time.ZoneId

class AtlasTimeOffScreen(
    private val activity: Activity,
    title: String,
    private val model: AtlasTimeOffModel,
) {
    val toolbar = Toolbar(activity).apply { this.title = title }
    private val content =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(16), dp(24), dp(24))
        }
    private val scroll = ScrollView(activity).apply { addView(content) }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(toolbar, LinearLayout.LayoutParams(-1, -2))
            addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
            setOnApplyWindowInsetsListener { root, insets ->
                root.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
                scroll.setPadding(0, 0, 0, insets.systemWindowInsetBottom)
                insets
            }
        }
    private var closed = false
    private val listener: () -> Unit = { render() }

    init {
        model.listener = listener
        render()
    }

    fun load() {
        model.load()
    }

    fun close() {
        closed = true
        if (model.listener === listener) model.listener = null
    }

    fun back(): Boolean {
        if (model.draft == null) return false
        model.discardDraft()
        return true
    }

    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()

    private fun text(
        value: String,
        heading: Boolean = false,
    ) {
        content.addView(
            TextView(activity).apply {
                text = value
                textSize = if (heading) 20f else 16f
                setPadding(0, dp(12), 0, dp(8))
                if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = heading
            },
        )
    }

    private fun button(
        label: String,
        enabled: Boolean = !model.busy,
        action: () -> Unit,
    ) {
        content.addView(
            Button(activity).apply {
                text = label
                isAllCaps = false
                minHeight = dp(48)
                isEnabled = enabled
                setOnClickListener { action() }
            },
            ViewGroup.LayoutParams(-1, -2),
        )
    }

    private fun render() {
        if (closed) return
        content.removeAllViews()
        model.error?.let {
            text(it)
            button("Refresh") { model.load() }
        }
        if (model.busy) text("Updating holidays…")
        val draft = model.draft
        if (draft != null) {
            text(if (draft.id == null) "Request holiday" else "Edit request", true)
            text("Dates are inclusive. Changing approved dates requires approval again.")
            button("First day away: ${draft.first}") { choose(draft.first) { model.dates(it, draft.last) } }
            button("Last day away: ${draft.last}") { choose(draft.last) { model.dates(draft.first, it) } }
            button(if (draft.id == null) "Request holiday" else "Save changes") { model.save() }
            button("Discard changes") { model.discardDraft() }
            return
        }
        button("Request holiday") { model.edit() }
        text("Full-day requests use the Berlin public holiday calendar. Working days exclude weekends and public holidays.")
        text("My requests", true)
        if (model.bookings.isEmpty() && !model.busy) text("No holiday requests yet.")
        for (booking in model.bookings) {
            text("${booking.first} – ${booking.last}", true)
            text(booking.status.replaceFirstChar(Char::uppercase))
            booking.days?.let { text("$it working days") }
            if (booking.incomplete) text("Public holiday calendar incomplete")
            if (booking.canEdit) button("Edit request") { model.edit(booking) }
            if (booking.canCancel) {
                button("Cancel holiday") {
                    AlertDialog
                        .Builder(activity)
                        .setTitle("Cancel this holiday?")
                        .setMessage("${booking.first} – ${booking.last}")
                        .setPositiveButton("Cancel holiday") { _, _ -> model.cancel(booking) }
                        .setNegativeButton("Keep holiday", null)
                        .show()
                }
            }
        }
        if (model.requestPages > 1) {
            text("Page ${model.requestsPage} of ${model.requestPages}")
            button("Previous requests", !model.busy && model.requestsPage > 1) { model.load(requests = model.requestsPage - 1) }
            button(
                "Next requests",
                !model.busy && model.requestsPage < model.requestPages,
            ) { model.load(requests = model.requestsPage + 1) }
        }
        text("Berlin public holidays", true)
        for (holiday in model.holidays) {
            text("${holiday.name}\n${holiday.date}")
        }
        if (model.holidays.isEmpty() && !model.busy) text("Public holidays will appear after the automatic calendar sync completes.")
        if (model.holidayPages > 1) {
            text("Page ${model.holidaysPage} of ${model.holidayPages}")
            button(
                "Previous public holidays",
                !model.busy && model.holidaysPage > 1,
            ) { model.load(publicHolidays = model.holidaysPage - 1) }
            button("Next public holidays", !model.busy && model.holidaysPage < model.holidayPages) {
                model.load(
                    publicHolidays =
                        model.holidaysPage + 1,
                )
            }
        }
        button("Refresh") { model.load() }
    }

    private fun choose(
        date: LocalDate,
        selected: (LocalDate) -> Unit,
    ) {
        DatePickerDialog(
            activity,
            { _, year, month, day -> selected(LocalDate.of(year, month + 1, day)) },
            date.year,
            date.monthValue - 1,
            date.dayOfMonth,
        ).apply {
            val zone = ZoneId.systemDefault()
            datePicker.minDate =
                LocalDate
                    .of(2000, 1, 1)
                    .atStartOfDay(zone)
                    .toInstant()
                    .toEpochMilli()
            datePicker.maxDate =
                LocalDate
                    .of(2100, 12, 31)
                    .atStartOfDay(zone)
                    .toInstant()
                    .toEpochMilli()
        }.show()
    }
}
