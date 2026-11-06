package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasTimeOffModel
import org.json.JSONObject
import java.time.LocalDate

internal fun checkTimeOffModel() {
    var sent: JSONObject? = null
    lateinit var finish: (Result<JSONObject>) -> Unit
    val model =
        AtlasTimeOffModel { action, complete ->
            sent = action
            finish = complete
        }
    model.edit()
    model.dates(LocalDate.of(2027, 6, 11), LocalDate.of(2027, 6, 7))
    check(model.draft?.first == model.draft?.last)
    model.save()
    check(model.busy && sent?.getString("action") == "create")
    check(sent?.getString("starts_on") == "2027-06-11" && sent?.getString("ends_on") == "2027-06-11")
    val originalRequest = sent
    model.save()
    model.discardDraft()
    check(sent === originalRequest && model.draft != null)
    finish(Result.failure(IllegalStateException("Dates overlap")))
    check(!model.busy && model.error == "Dates overlap" && model.draft != null)
    model.save()
    finish(Result.success(JSONObject()))
    check(model.draft == null && model.busy && sent?.getString("action") == "list")
    finish(Result.failure(IllegalStateException("Reload failed")))
    check(model.draft == null && !model.busy && model.error == "Reload failed")
    model.load(2, 3)
    check(sent?.getInt("requests_page") == 2 && sent?.getInt("holidays_page") == 3)
    finish(
        Result.success(
            JSONObject("""{"requests":{"items":[],"page":2,"total_pages":4},"public_holidays":{"items":[],"page":3,"total_pages":5}}"""),
        ),
    )
    check(!model.busy && model.error == null && model.requestsPage == 2 && model.holidaysPage == 3)
    val cancelled = AtlasTimeOffModel.Booking("preview", "2027-06-07", "2027-06-11", "cancelled", 5, false)
    val before = sent
    model.cancel(cancelled)
    model.edit(cancelled)
    check(model.draft == null && sent === before)
    val rejected = cancelled.copy(status = "rejected")
    check(rejected.canEdit && !rejected.canCancel)
    model.edit(rejected)
    model.save()
    check(sent?.getString("action") == "update" && sent?.getString("id") == "preview")
    finish(Result.success(JSONObject()))
    finish(
        Result.success(
            JSONObject("""{"requests":{"items":[],"page":1,"total_pages":0},"public_holidays":{"items":[],"page":1,"total_pages":0}}"""),
        ),
    )
    check(!model.busy && model.draft == null)
}
