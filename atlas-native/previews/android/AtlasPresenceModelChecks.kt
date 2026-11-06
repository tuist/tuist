package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasPresenceModel
import org.json.JSONObject

internal fun checkPresenceModel() {
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasPresenceModel { action, done -> pending.add(action to done) }

    fun complete(
        action: String,
        value: String,
    ) {
        val index = pending.indexOfFirst { it.first.getString("action") == action }
        check(index >= 0)
        pending.removeAt(index).second(Result.success(JSONObject(value)))
    }
    model.show("tasks", "first-record")
    model.setActive(true)
    complete("open", """{"connection":"fixture-connection"}""")
    complete("update", """{"updated":true}""")
    model.show("accounts", "second-record")
    complete("update", """{"updated":true}""")
    complete(
        "next",
        """{"sequence":1,"location":{"resource":"tasks","id":"first-record"},"people":[{"id":"other","name":"Colleague","email":"colleague@example.org","online":true,"here":true}]}""",
    )
    check(model.people.isEmpty())
    complete(
        "next",
        """{"sequence":2,"location":{"resource":"accounts","id":"second-record"},"people":[{"id":"other","name":"Colleague","email":"colleague@example.org","online":true,"here":true}]}""",
    )
    check(model.people.single().here)
    var stopped = false
    model.stop { stopped = true }
    check(model.people.isEmpty() && !stopped)
    complete("close", """{"closed":true}""")
    check(stopped)
    complete(
        "next",
        """{"sequence":3,"location":{"resource":"accounts","id":"second-record"},"people":[{"id":"other","name":"Late response","email":"colleague@example.org","online":true,"here":true}]}""",
    )
    check(model.people.isEmpty())
    model.setActive(true)
    model.setActive(false)
    complete("open", """{"connection":"late-open"}""")
    check(pending.single().first.getString("action") == "close")
    complete("close", """{"closed":true}""")
}
