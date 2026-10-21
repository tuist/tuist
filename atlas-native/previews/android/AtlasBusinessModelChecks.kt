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

    model.load(2, "follow-up")
    check(pending.single().first.getString("query") == "follow-up" && pending.single().first.getInt("page") == 2)
    succeed()
    check(model.page == 2 && model.total == 1 && model.items.isEmpty() && model.query == "follow-up")
    model.load(1, "")
    succeed()
    check(model.items.size == 2 && model.total == 3 && model.pages == 2)
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
    check(invoices.selected == null && invoices.items.size == 1 && invoices.total == 1)

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
