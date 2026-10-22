package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasBusinessModel
import dev.tuist.atlas.AtlasProfileModel
import dev.tuist.atlas.AuthFailure
import org.json.JSONObject

fun main() {
    checkBusinessModels()
    println("PASS: business and profile model checks (no network)")
}

internal fun checkBusinessModels() {
    checkBusinessLists()
    val fixtures = AtlasBusinessFixtures()
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasBusinessModel("tasks") { action, done -> pending.add(action to done) }

    fun succeed() {
        val (action, done) = pending.removeAt(0)
        done(Result.success(fixtures.execute(action)))
    }

    fun fail() {
        pending.removeAt(0).second(Result.failure(IllegalStateException("Preview failure")))
    }

    model.load(search = "follow-up")
    check(pending.single().first.getString("query") == "follow-up" && pending.single().first.getInt("page") == 1)
    succeed()
    check(model.page == 1 && model.total == 1 && model.items.single().id == "task-3" && model.query == "follow-up")
    model.load(search = "")
    succeed()
    check(model.items.size == 2 && model.total == 6 && model.pages == 3)
    check(model.options.getValue("users").map { it.id } == listOf("user-1", "user-2"))
    model.edit()
    model.field("title", "Keep this draft")
    model.field("due_on", "2027-07-14")
    model.field("status", "completed")
    model.save()
    val save = pending.single().first
    check(model.saving && model.busy && model.back() && model.draft != null)
    model.save()
    check(pending.size == 1)
    check(save.getJSONObject("fields").getString("title") == "Keep this draft")
    check(save.getJSONObject("fields").getString("due_on") == "2027-07-14")
    check(!save.getJSONObject("fields").has("remind_at") && !save.getJSONObject("fields").has("status"))
    fail()
    check(!model.busy && !model.saving && model.draft?.fields?.get("title") == "Keep this draft")
    model.save()
    succeed()
    check(model.draft == null && model.selected?.get("title") == "Keep this draft" && model.busy && !model.saving)
    check(pending.single().first.getString("action") == "list")
    fail()
    check(model.selected?.get("title") == "Keep this draft" && model.notice == "Saved." && model.error != null)
    model.save()
    check(pending.isEmpty())
    model.complete(model.selected!!)
    check(pending.single().first.getString("action") == "complete")
    succeed()
    fail()
    check(model.selected?.get("status") == "completed")
    model.complete(model.selected!!)
    check(pending.isEmpty())
    model.back()
    model.show(model.items.first())
    val staleShow = pending.removeAt(0)
    check(model.back() && model.selected == null)
    staleShow.second(Result.success(fixtures.execute(staleShow.first)))
    check(model.selected == null && !model.busy)
    model.load()
    val before = model.items
    fail()
    check(model.items == before)
    model.load()
    val late = pending.removeAt(0)
    model.clear()
    late.second(Result.success(fixtures.execute(late.first)))
    check(model.items.isEmpty() && model.selected == null && model.draft == null)

    val invoices = AtlasBusinessModel("invoices") { action, done -> done(Result.success(fixtures.execute(action))) }
    invoices.load()
    check(invoices.summary.groupBy { it.currency }.keys == setOf("EUR", "USD"))
    check(
        invoices.summary
            .first()
            .amount
            .signum() == 0,
    )
    val imported = invoices.items.first { !it.canEdit }
    invoices.edit(imported)
    invoices.delete(imported)
    check(invoices.draft == null && invoices.items.contains(imported))
    invoices.show(invoices.items.first { it.canEdit })
    invoices.delete(invoices.selected!!)
    check(invoices.selected == null && invoices.items.size == 2 && invoices.total == 2)

    val accounts = AtlasBusinessModel("accounts") { action, done -> done(Result.success(fixtures.execute(action))) }
    accounts.load()
    accounts.edit(accounts.items.first())
    check(accounts.draft?.fields?.get("next_renewal_date") == "2027-08-15")
    check(accounts.options.getValue("deal_stages").map { it.id } == listOf("discovery", "closed_won"))
    accounts.field("current_value", "765.43")
    accounts.field("next_renewal_date", "")
    accounts.save()
    check(accounts.draft == null && accounts.selected?.get("current_value") == "765.43")
    check(accounts.selected?.get("next_renewal_date") == "")

    var revoked = false
    val access =
        AtlasBusinessModel("accounts") { action, done ->
            if (revoked) {
                done(Result.failure(AuthFailure("forbidden", "Access revoked")))
            } else {
                done(Result.success(fixtures.execute(action)))
            }
        }
    access.load()
    check(access.items.isNotEmpty() && access.canWrite)
    revoked = true
    access.show(access.items.first())
    check(access.items.isEmpty() && access.selected == null && access.summary.isEmpty() && !access.canWrite)

    lateinit var completeProfile: (Result<JSONObject>) -> Unit
    val profile =
        AtlasProfileModel { action, done ->
            check(action.getString("resource") == "profile" && action.getString("action") == "list")
            completeProfile = done
        }
    profile.load()
    completeProfile(Result.success(fixtures.execute(JSONObject().put("resource", "profile"))))
    check(profile.name == "Alex Example" && profile.email == "alex@example.org" && profile.version == "1.2.3-demo")
    profile.load()
    profile.clear()
    completeProfile(Result.success(fixtures.execute(JSONObject().put("resource", "profile"))))
    check(profile.name.isEmpty() && profile.email.isEmpty() && profile.version.isEmpty())
}

private fun checkBusinessLists() {
    for ((resource, count) in listOf("tasks" to 6, "accounts" to 3, "invoices" to 3)) {
        val fixtures = AtlasBusinessFixtures()
        val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
        val model = AtlasBusinessModel(resource) { action, done -> pending.add(action to done) }

        fun finish() {
            val (action, done) = pending.removeAt(0)
            done(Result.success(fixtures.execute(action)))
        }
        model.load()
        model.load()
        check(pending.size == 1)
        finish()
        val firstIds = model.items.map { it.id }
        model.rememberScroll(137)
        model.loadMore()
        model.loadMore()
        check(pending.size == 1 && model.loadingMore && model.items.map { it.id } == firstIds)
        pending.removeAt(0).second(Result.failure(IllegalStateException("Next page failed")))
        check(model.nextPageError == "Next page failed" && model.error == null && model.page == 1 && !model.loadingMore)
        repeat(3) { model.loadMore() }
        check(pending.isEmpty() && model.listScrollY == 137)
        model.retryNextPage()
        model.retryNextPage()
        check(pending.size == 1 && pending.single().first.getInt("page") == 2)
        val (next, done) = pending.removeAt(0)
        val response = fixtures.execute(next)
        val overlap =
            JSONObject()
                .put("id", firstIds.last())
                .put("fields", JSONObject().put("description", "Updated overlap"))
                .put("can_edit", true)
                .put("can_delete", true)
        response.getJSONArray("items").put(overlap)
        done(Result.success(response))
        check(model.items.take(2).map { it.id } == firstIds && model.items[1]["description"] == "Updated overlap")
        check(
            model.items
                .map { it.id }
                .distinct()
                .size == model.items.size && model.listScrollY == 137 && model.nextPageError == null,
        )
        if (resource == "tasks") {
            model.loadMore()
            finish()
        }
        check(model.items.size == count && model.page == model.pages)
        model.loadMore()
        check(pending.isEmpty())
        model.load()
        check(pending.single().first.getInt("page") == 1 && model.listScrollY == 0)
        finish()
        check(model.items.map { it.id } == firstIds)
        model.loadMore()
        val stale = pending.removeAt(0)
        val filterKey = if (resource == "accounts") "segment" else "status"
        val filterValue =
            when (resource) {
                "tasks" -> "completed"
                "accounts" -> "prospect"
                else -> "extracted"
            }
        model.load(filters = mapOf(filterKey to filterValue))
        check(model.items.isEmpty() && model.filters == mapOf(filterKey to filterValue))
        check(
            pending
                .single()
                .first
                .getJSONObject("filters")
                .getString(filterKey) == filterValue,
        )
        finish()
        val filtered = model.items
        stale.second(Result.success(fixtures.execute(stale.first)))
        check(model.items == filtered && model.total == 1 && model.page == 1 && !model.busy)
        model.clear()
        model.loadMore()
        check(pending.isEmpty())
    }

    val fixtures = AtlasBusinessFixtures()
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasBusinessModel("tasks") { action, done -> pending.add(action to done) }
    model.load()
    model.load(search = "follow-up", filters = mapOf("status" to "open"))
    model.load(
        search = "quarter",
        filters =
            mapOf(
                "status" to "",
                "reminder" to "upcoming",
                "group_by" to "reminder",
                "unsupported" to "ignored",
            ),
    )
    check(pending.size == 3 && model.query == "quarter" && model.filters == mapOf("reminder" to "upcoming", "group_by" to "reminder"))
    val latest = pending.removeAt(2)
    latest.second(Result.success(fixtures.execute(latest.first)))
    check(model.items.single().id == "task-5" && model.items.single()["reminder_group"] == "upcoming")
    pending[1].second(Result.success(fixtures.execute(pending[1].first)))
    pending[0].second(Result.failure(IllegalStateException("Old failure")))
    check(model.items.single().id == "task-5" && model.error == null && !model.busy)
    pending.clear()
    model.load(search = "", filters = mapOf("group_by" to "reminder"))

    fun finish() {
        val (action, done) = pending.removeAt(0)
        done(Result.success(fixtures.execute(action)))
    }
    finish()
    check(model.items.map { it.id } == listOf("task-1", "task-4"))
    model.loadMore()
    finish()
    check(model.items.map { it["reminder_group"] } == listOf("overdue", "overdue", "upcoming", "none"))
    model.loadMore()
    model.load(search = "", filters = emptyMap())
    check(pending.size == 2 && pending.last().first.getInt("page") == 1)
    val refresh = pending.removeAt(1)
    refresh.second(Result.success(fixtures.execute(refresh.first)))
    pending.removeAt(0).second(Result.failure(IllegalStateException("Old next-page failure")))
    check(model.items.map { it.id } == listOf("task-1", "task-2") && model.nextPageError == null && model.filters.isEmpty())
}
