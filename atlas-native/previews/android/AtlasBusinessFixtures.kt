package dev.tuist.atlas.preview

import org.json.JSONArray
import org.json.JSONObject

// Isolated preview data. The production APK never includes this source directory.
internal class AtlasBusinessFixtures {
    private val records =
        mutableMapOf(
            "tasks" to
                mutableListOf(
                    row(
                        "task-1",
                        """{"title":"Prepare renewal proposal","description":"Review next year’s scope with the team.","status":"open","assignee_id":"user-1","assignee_name":"Alex Example","account_id":"account-1","account_name":"Sample Studio","due_on":"2027-06-11","remind_at":"2027-06-10T07:00:00Z"}""",
                    ),
                    row(
                        "task-2",
                        """{"title":"Review mobile release","description":"Check Android and iOS builds.","status":"completed","assignee_name":"Jordan Example"}""",
                    ),
                    row("task-3", """{"title":"Send follow-up","status":"open","assignee_name":"Alex Example"}"""),
                ),
            "accounts" to
                mutableListOf(
                    row(
                        "account-1",
                        """{"name":"Sample Studio","description":"Example customer account","primary_domain":"sample.example.org","segment":"customer","status":"active","deal_stage":"closed_won","currency":"EUR","current_value":"12500.50","next_renewal_date":"2027-08-15","legal_name":"Sample Studio GmbH","url":"https://sample.example.org","hosting":"cloud","plan_tier":"pro"}""",
                    ),
                    row(
                        "account-2",
                        """{"name":"Example Labs","primary_domain":"labs.example.org","segment":"prospect","status":"trial","deal_stage":"discovery"}""",
                    ),
                ),
            "invoices" to
                mutableListOf(
                    row(
                        "invoice-1",
                        """{"vendor_name":"Example Hosting","invoice_number":"INV-2027-06","invoice_date":"2027-06-01","due_date":"2027-06-30","total_amount_value":"150.25","total_amount_currency":"EUR","status":"needs_review"}""",
                    ),
                    row(
                        "invoice-2",
                        """{"vendor_name":"Example imported invoice","invoice_number":"IMP-42","invoice_date":"2027-05-15","total_amount_value":"95.10","total_amount_currency":"USD","status":"extracted"}""",
                        false,
                    ),
                ),
        )
    private var nextId = 10

    fun execute(action: JSONObject): JSONObject {
        if (action.getString("resource") == "profile") {
            return JSONObject("""{"server_version":"1.2.3-demo","user":{"name":"Alex Example","email":"alex@example.org"}}""")
        }
        val resource = action.getString("resource")
        val rows = records.getValue(resource)
        val id = action.optString("id")
        return when (action.getString("action")) {
            "list" -> {
                val matches = rows.filter { it.getJSONObject("fields").toString().contains(action.optString("query"), ignoreCase = true) }
                val page = action.optInt("page", 1).coerceAtLeast(1)
                JSONObject()
                    .put("items", JSONArray(matches.drop((page - 1) * 2).take(2)))
                    .put("page", page)
                    .put("total_pages", (matches.size + 1) / 2)
                    .put("total_count", matches.size)
                    .put("can_write", true)
                    .put("options", options(resource))
                    .put(
                        "summary",
                        if (resource ==
                            "invoices"
                        ) {
                            JSONArray(
                                """[{"month":"2027-04","currency":"EUR","amount":"0.00"},{"month":"2027-05","currency":"EUR","amount":"75.00"},{"month":"2027-06","currency":"EUR","amount":"150.25"},{"month":"2027-05","currency":"USD","amount":"95.10"},{"month":"2027-06","currency":"USD","amount":"0.00"}]""",
                            )
                        } else {
                            JSONArray()
                        },
                    )
            }
            "show" -> JSONObject().put("item", rows.first { it.getString("id") == id })
            "delete" -> {
                rows.removeAll { it.getString("id") == id }
                JSONObject().put("deleted", true)
            }
            "complete" -> {
                val value = rows.first { it.getString("id") == id }
                value.getJSONObject("fields").put("status", "completed")
                JSONObject().put("item", value)
            }
            else -> {
                val value = rows.firstOrNull { it.getString("id") == id } ?: row("new-${nextId++}", "{}").also { rows.add(0, it) }
                val fields = value.getJSONObject("fields")
                val changes = action.getJSONObject("fields")
                changes.keys().forEach { key ->
                    check(changes.get(key) is String) { "Native attributes must be strings; clear optional values with an empty string." }
                    fields.put(key, changes.getString(key))
                }
                if (resource == "tasks") {
                    if (!fields.has("status")) fields.put("status", "open")
                    fields.put("assignee_name", "Alex Example")
                }
                JSONObject().put("item", value)
            }
        }
    }

    private fun options(resource: String) =
        JSONObject()
            .put("users", JSONArray("""[{"id":"user-1","name":"Alex Example"},{"id":"user-2","name":"Jordan Example"}]"""))
            .put("accounts", JSONArray("""[{"id":"account-1","name":"Sample Studio"},{"id":"account-2","name":"Example Labs"}]"""))
            .put("segments", JSONArray("""["customer","lead","prospect"]"""))
            .put(
                "statuses",
                if (resource ==
                    "invoices"
                ) {
                    JSONArray("""["extracted","needs_review","failed"]""")
                } else {
                    JSONArray("""["active","churned","paused","trial"]""")
                },
            ).put("deal_stages", JSONArray("""["discovery","closed_won"]"""))

    private fun row(
        id: String,
        fields: String,
        writable: Boolean = true,
    ) = JSONObject()
        .put("id", id)
        .put("fields", JSONObject(fields))
        .put("can_edit", writable)
        .put("can_delete", writable)
}
