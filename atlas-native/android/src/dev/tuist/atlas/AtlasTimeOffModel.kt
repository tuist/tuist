package dev.tuist.atlas

import org.json.JSONObject
import java.time.LocalDate

class AtlasTimeOffModel(
    private val request: (JSONObject, (Result<JSONObject>) -> Unit) -> Unit,
) {
    data class Booking(
        val id: String,
        val first: String,
        val last: String,
        val status: String,
        val days: Int?,
        val incomplete: Boolean,
    ) {
        val canEdit get() = status != "cancelled"
        val canCancel get() = status == "pending" || status == "approved"
    }

    data class Holiday(
        val name: String,
        val date: String,
    )

    data class Draft(
        val id: String?,
        val first: LocalDate,
        val last: LocalDate,
    )

    var listener: (() -> Unit)? = null
    var bookings = emptyList<Booking>()
        private set
    var holidays = emptyList<Holiday>()
        private set
    var requestsPage = 1
        private set
    var requestPages = 0
        private set
    var holidaysPage = 1
        private set
    var holidayPages = 0
        private set
    var busy = false
        private set
    var error: String? = null
        private set
    var draft: Draft? = null
        private set

    fun edit(booking: Booking? = null) {
        if (busy || booking?.canEdit == false) return
        draft =
            Draft(
                booking?.id,
                booking?.first?.let(LocalDate::parse) ?: LocalDate.now(),
                booking?.last?.let(LocalDate::parse) ?: LocalDate.now(),
            )
        error = null
        listener?.invoke()
    }

    fun dates(
        first: LocalDate,
        last: LocalDate,
    ) {
        if (busy) return
        draft = draft?.copy(first = first, last = maxOf(first, last))
        error = null
        listener?.invoke()
    }

    fun discardDraft() {
        if (busy) return
        draft = null
        error = null
        listener?.invoke()
    }

    fun load(
        requests: Int = requestsPage,
        publicHolidays: Int = holidaysPage,
    ) {
        if (busy) return
        busy = true
        error = null
        listener?.invoke()
        fetch(requests, publicHolidays)
    }

    private fun fetch(
        requests: Int,
        publicHolidays: Int,
    ) {
        request(JSONObject().put("action", "list").put("requests_page", requests).put("holidays_page", publicHolidays)) { result ->
            result.fold({ response ->
                try {
                    val page = response.getJSONObject("requests")
                    val publicPage = response.getJSONObject("public_holidays")
                    val rows = page.getJSONArray("items")
                    val days = publicPage.getJSONArray("items")
                    val nextBookings =
                        List(rows.length()) { index ->
                            val row = rows.getJSONObject(index)
                            Booking(
                                row.getString("id"),
                                LocalDate.parse(row.getString("starts_on")).toString(),
                                LocalDate.parse(row.getString("ends_on")).toString(),
                                row.getString("status"),
                                if (row.isNull("working_days")) null else row.getInt("working_days"),
                                (row.optJSONArray("missing_years")?.length() ?: 0) > 0,
                            )
                        }
                    val nextHolidays =
                        List(
                            days.length(),
                        ) { index -> days.getJSONObject(index).let { Holiday(it.getString("name"), it.getString("date")) } }
                    bookings = nextBookings
                    holidays = nextHolidays
                    requestsPage = page.getInt("page")
                    requestPages = page.getInt("total_pages")
                    holidaysPage = publicPage.getInt("page")
                    holidayPages = publicPage.getInt("total_pages")
                } catch (_: Exception) {
                    error = "Atlas returned an invalid holiday response. Try refreshing."
                }
            }, { error = it.message ?: "Could not load holidays. Try again." })
            busy = false
            listener?.invoke()
        }
    }

    fun save() {
        val value = draft ?: return
        val action =
            JSONObject()
                .put(
                    "action",
                    if (value.id ==
                        null
                    ) {
                        "create"
                    } else {
                        "update"
                    },
                ).put("starts_on", value.first.toString())
                .put("ends_on", value.last.toString())
        value.id?.let { action.put("id", it) }
        mutate(action)
    }

    fun cancel(booking: Booking) {
        if (booking.canCancel) mutate(JSONObject().put("action", "cancel").put("id", booking.id))
    }

    private fun mutate(action: JSONObject) {
        if (busy) return
        busy = true
        error = null
        listener?.invoke()
        request(action) { result ->
            result.fold({
                draft = null
                listener?.invoke()
                fetch(1, holidaysPage)
            }, {
                error = it.message ?: "Could not save holidays. Try again."
                busy = false
                listener?.invoke()
            })
        }
    }
}
