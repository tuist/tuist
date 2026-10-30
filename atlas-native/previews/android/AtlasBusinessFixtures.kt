package dev.tuist.atlas.preview

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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
                        """{"title":"Prepare renewal proposal","description":"Review next year’s scope with the team.","status":"open","assignee_id":"user-1","assignee_name":"Alex Example","account_id":"account-1","account_name":"Sample Studio","due_on":"2099-06-11","remind_at":"2026-06-10T07:00:00Z","reminder_group":"overdue"}""",
                    ),
                    row(
                        "task-2",
                        """{"title":"Review mobile release","description":"Check Android and iOS builds.","status":"completed","assignee_id":"user-2","assignee_name":"Jordan Example","reminder_group":"completed"}""",
                    ),
                    row(
                        "task-3",
                        """{"title":"Send follow-up","status":"open","assignee_id":"user-1","assignee_name":"Alex Example","reminder_group":"none"}""",
                    ),
                    row(
                        "task-4",
                        """{"title":"Check contract details","status":"open","assignee_id":"user-2","assignee_name":"Jordan Example","remind_at":"2026-05-01T09:00:00Z","reminder_group":"overdue"}""",
                    ),
                    row(
                        "task-5",
                        """{"title":"Plan next quarter","status":"open","assignee_id":"user-1","assignee_name":"Alex Example","due_on":"2020-01-01","remind_at":"2099-01-01T09:00:00Z","reminder_group":"upcoming"}""",
                    ),
                    row(
                        "task-6",
                        """{"title":"Review onboarding notes","status":"open","assignee_id":"user-2","assignee_name":"Jordan Example","reminder_group":"none"}""",
                    ),
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
                    row("account-3", """{"name":"Northwind Demo","segment":"lead","status":"paused","deal_stage":"discovery"}"""),
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
                    row(
                        "invoice-3",
                        """{"vendor_name":"Demo Office","invoice_number":"OFF-1","invoice_date":"2027-06-02","total_amount_value":"25.00","total_amount_currency":"EUR","status":"needs_review"}""",
                    ),
                ),
        )
    private var nextId = 10
    private var profileDescription = ""

    fun execute(action: JSONObject): JSONObject {
        if (action.getString("resource") == "profile") {
            if (action.optString("action") == "update_profile") profileDescription = action.getString("description").trim()
            return JSONObject("""{"server_version":"1.2.3-demo","user":{"name":"Alex Example","email":"alex@example.org"}}""").apply {
                getJSONObject("user").put("description", profileDescription)
            }
        }
        val resource = action.getString("resource")
        val rows = records.getValue(resource)
        val id = action.optString("id")
        return when (action.getString("action")) {
            "list" -> {
                val filters = action.optJSONObject("filters") ?: JSONObject()
                var matches =
                    rows.filter { row ->
                        val fields = row.getJSONObject("fields")
                        fields.toString().contains(action.optString("query"), ignoreCase = true) &&
                            filters.keys().asSequence().all { key ->
                                val expected = filters.getString(key)
                                key == "group_by" || expected.isEmpty() ||
                                    fields.optString(if (key == "reminder") "reminder_group" else key) == expected
                            }
                    }
                if (filters.optString("group_by") == "reminder") {
                    val order = listOf("overdue", "upcoming", "none", "completed")
                    matches = matches.sortedBy { order.indexOf(it.getJSONObject("fields").optString("reminder_group")) }
                }
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
                value.getJSONObject("fields").put("status", "completed").put("reminder_group", "completed")
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
                    if (!fields.has("reminder_group")) fields.put("reminder_group", "none")
                    fields.put("assignee_name", "Alex Example")
                }
                JSONObject().put("item", value)
            }
        }
    }

    fun logo(
        domain: String,
        completion: (Bitmap?) -> Unit,
    ): () -> Unit {
        val bitmap =
            if (domain == "sample.example.org") {
                Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888).apply {
                    val canvas = Canvas(this)
                    canvas.drawColor(Color.rgb(25, 100, 160))
                    canvas.drawText(
                        "S",
                        64f,
                        96f,
                        Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = Color.WHITE
                            textSize = 90f
                            textAlign = Paint.Align.CENTER
                        },
                    )
                }
            } else {
                null
            }
        completion(bitmap)
        return {}
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
