package dev.tuist.atlas

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal

class AtlasBusinessModel(
    val resource: String,
    private val request: (JSONObject, (Result<JSONObject>) -> Unit) -> Unit,
) {
    data class Record(
        val id: String,
        val fields: Map<String, String>,
        val canEdit: Boolean,
        val canDelete: Boolean,
    ) {
        operator fun get(key: String) = fields[key].orEmpty()
    }

    data class Choice(
        val id: String,
        val name: String,
    )

    data class Month(
        val month: String,
        val currency: String,
        val amount: BigDecimal,
    )

    data class Draft(
        val id: String?,
        val fields: MutableMap<String, String>,
    )

    var listener: (() -> Unit)? = null
    var items = emptyList<Record>()
        private set
    var selected: Record? = null
        private set
    var draft: Draft? = null
        private set
    var options = emptyMap<String, List<Choice>>()
        private set
    var summary = emptyList<Month>()
        private set
    var query = ""
        private set
    var page = 1
        private set
    var pages = 0
        private set
    var total = 0
        private set
    var canWrite = false
        private set
    var loaded = false
        private set
    var busy = false
        private set
    var saving = false
        private set
    var error: String? = null
        private set
    var notice: String? = null
        private set
    private var generation = 0
    private var cleared = false
    val canBack get() = saving || draft != null || selected != null || query.isNotEmpty()

    init {
        require(resource in listOf("tasks", "accounts", "invoices"))
    }

    fun load(
        nextPage: Int = page,
        search: String = query,
    ) {
        if (busy || draft != null || cleared) return
        fetch(nextPage, search)
    }

    private fun fetch(
        nextPage: Int,
        search: String,
    ) {
        send(JSONObject().put("action", "list").put("page", nextPage).put("query", search)) { response ->
            val rows = response.getJSONArray("items").objects().map(::record)
            val choices = response.optJSONObject("options") ?: JSONObject()
            val nextOptions =
                choices.keys().asSequence().associateWith { key ->
                    val values = choices.getJSONArray(key)
                    List(values.length()) { index ->
                        when (val value = values.get(index)) {
                            is JSONObject -> Choice(value.getString("id"), value.getString("name"))
                            else -> Choice(value.toString(), value.toString())
                        }
                    }
                }
            val months =
                response.optJSONArray("summary")?.objects().orEmpty().map {
                    Month(it.getString("month"), it.getString("currency"), it.getString("amount").toBigDecimal())
                }
            val nextPageNumber = response.getInt("page")
            val nextPages = response.getInt("total_pages")
            val nextTotal = response.getInt("total_count")
            val write = response.getBoolean("can_write")
            items = rows
            options = nextOptions
            summary = months
            page = nextPageNumber
            pages = nextPages
            total = nextTotal
            query = search
            canWrite = write
            loaded = true
        }
    }

    fun show(value: Record) {
        if (busy || cleared) return
        selected = value
        notice = null
        send(JSONObject().put("action", "show").put("id", value.id)) { response ->
            selected = record(response.getJSONObject("item"))
        }
    }

    fun edit(value: Record? = null) {
        if (busy || cleared || (value == null && !canWrite) || value?.canEdit == false) return
        draft = Draft(value?.id, value?.fields?.toMutableMap() ?: mutableMapOf())
        error = null
        notice = null
        listener?.invoke()
    }

    fun field(
        key: String,
        value: String,
    ) {
        if (!saving && key in editableFields) draft?.fields?.set(key, value)
    }

    fun back(): Boolean {
        if (saving) return true
        if (draft != null) {
            draft = null
        } else if (selected != null) {
            selected = null
            generation += 1
            busy = false
        } else if (query.isNotEmpty()) {
            if (!busy) load(1, "")
            return true
        } else {
            return false
        }
        error = null
        notice = null
        listener?.invoke()
        return true
    }

    fun save() {
        val value = draft ?: return
        val fields = JSONObject()
        editableFields.forEach { key ->
            val field = value.fields[key]?.takeIf { it.isNotBlank() }
            if (field != null) {
                val normalized =
                    if (key in listOf("current_value", "total_amount_value")) {
                        field.replace(
                            java.text.DecimalFormatSymbols
                                .getInstance()
                                .decimalSeparator,
                            '.',
                        )
                    } else {
                        field
                    }
                fields.put(key, normalized)
            } else if (value.id != null) {
                fields.put(key, "")
            }
        }
        val action = JSONObject().put("action", if (value.id == null) "create" else "update").put("fields", fields)
        value.id?.let { action.put("id", it) }
        mutate(action)
    }

    fun delete(value: Record) {
        if (value.canDelete) mutate(JSONObject().put("action", "delete").put("id", value.id))
    }

    fun complete(value: Record) {
        if (resource == "tasks" && value.canEdit && value["status"] != "completed") {
            mutate(JSONObject().put("action", "complete").put("id", value.id))
        }
    }

    private fun mutate(action: JSONObject) {
        if (busy || cleared) return
        saving = true
        send(action) { response ->
            if (action.getString("action") == "delete") {
                check(response.getBoolean("deleted"))
                items = items.filterNot { it.id == action.getString("id") }
                total = maxOf(0, total - 1)
                selected = null
                notice = "Deleted."
            } else {
                val saved = record(response.getJSONObject("item"))
                items = items.map { if (it.id == saved.id) saved else it }
                selected = saved
                notice = "Saved."
            }
            draft = null
            saving = false
            // The successful result is already applied. A failed reload must never reopen a create draft.
            busy = false
            fetch(1, query)
        }
    }

    fun clear() {
        cleared = true
        generation += 1
        listener = null
        items = emptyList()
        selected = null
        draft = null
        options = emptyMap()
        summary = emptyList()
        query = ""
        error = null
        notice = null
    }

    private fun send(
        action: JSONObject,
        accept: (JSONObject) -> Unit,
    ) {
        busy = true
        error = null
        val identity = ++generation
        listener?.invoke()
        request(action.put("resource", resource)) { result ->
            if (cleared || identity != generation) return@request
            busy = false
            result.fold({ response ->
                try {
                    accept(response)
                } catch (_: Exception) {
                    error = "Atlas returned an invalid response. Refresh before trying again."
                }
            }, {
                if (it is AuthFailure && it.kind == "forbidden" && action.getString("action") in listOf("list", "show")) {
                    items = emptyList()
                    selected = null
                    options = emptyMap()
                    summary = emptyList()
                    canWrite = false
                    loaded = false
                }
                error = it.message ?: "Could not complete the request. Try again."
            })
            if (identity == generation) saving = false
            listener?.invoke()
        }
    }

    val editableFields: List<String>
        get() =
            when (resource) {
                "tasks" -> listOf("title", "description", "assignee_id", "account_id", "due_on", "remind_at")
                "accounts" ->
                    listOf(
                        "name",
                        "description",
                        "primary_domain",
                        "segment",
                        "status",
                        "deal_stage",
                        "currency",
                        "current_value",
                        "next_renewal_date",
                        "legal_name",
                        "url",
                        "hosting",
                        "plan_tier",
                    )
                else ->
                    listOf(
                        "vendor_name",
                        "invoice_number",
                        "invoice_date",
                        "due_date",
                        "total_amount_value",
                        "total_amount_currency",
                        "status",
                    )
            }

    private fun record(value: JSONObject): Record {
        val fields = value.getJSONObject("fields")
        return Record(
            value.getString("id"),
            fields.keys().asSequence().associateWith { if (fields.isNull(it)) "" else fields.getString(it) },
            value.getBoolean("can_edit"),
            value.getBoolean("can_delete"),
        )
    }

    private fun JSONArray.objects() = List(length()) { getJSONObject(it) }
}
