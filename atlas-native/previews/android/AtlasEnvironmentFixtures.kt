package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasCodingRepositories
import org.json.JSONArray
import org.json.JSONObject

// Isolated demo data: never enrolls a machine or accesses GitHub.
internal class AtlasEnvironmentFixtures {
    private var settings = JSONObject("""{"installation_id":"42","default_repository":"acme/mobile"}""")
    private var repository: String? = "acme/mobile"
    private var environment: String? = null
    private var project: String? = null

    fun execute(action: JSONObject): JSONObject =
        when (action.getString("action")) {
            "repositories" ->
                JSONObject()
                    .put("settings", JSONObject(settings.toString()))
                    .put("installations", JSONArray("""[{"id":"42","name":"Acme"},{"id":"73","name":"Example Labs"}]"""))
                    .put(
                        "repositories",
                        JSONArray(
                            if (action.optString("installation_id", settings.optString("installation_id")) == "73") {
                                """[{"full_name":"example/api"}]"""
                            } else {
                                """[{"full_name":"acme/mobile"},{"full_name":"acme/server"}]"""
                            },
                        ),
                    )
            "update_repositories" ->
                JSONObject()
                    .put("installation_id", action.opt("installation_id"))
                    .put("default_repository", action.opt("default_repository"))
                    .also { settings = JSONObject(it.toString()) }
            "list" ->
                JSONObject()
                    .put("providers", JSONArray("""[{"id":"tuist","name":"Tuist"}]"""))
                    .put(
                        "environments",
                        JSONArray(
                            """[{"id":"demo-mac","name":"Demo Mac","enabled":true,"online":true,
                "projects":[{"id":"mobile","name":"Mobile","coding":true,"repository":"acme/mobile"}]}]""",
                        ),
                    )
            "selection", "select", "start_provider" -> {
                if (action.getString("action") != "selection") {
                    repository = if (action.isNull("repository")) null else action.getString("repository")
                    environment = if (action.isNull("environment_id")) null else action.getString("environment_id")
                    project = if (action.isNull("project_id")) null else action.getString("project_id")
                }
                JSONObject().put(
                    "thread",
                    JSONObject()
                        .put("id", action.getString("thread_id"))
                        .put("repository", repository ?: JSONObject.NULL)
                        .put("environment_id", environment ?: JSONObject.NULL)
                        .put("project_id", project ?: JSONObject.NULL),
                )
            }
            else -> JSONObject()
        }
}

internal fun checkCodingRepositorySettings() {
    val fixtures = AtlasEnvironmentFixtures()
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasCodingRepositories { action, done -> pending.add(action to done) }

    fun succeed() {
        val (action, done) = pending.removeAt(0)
        done(Result.success(fixtures.execute(action)))
    }
    model.load()
    model.load()
    check(pending.size == 1)
    succeed()
    check(model.repository == "acme/mobile" && !model.dirty)
    model.chooseInstallation("73")
    check(model.repository == null && model.catalog!!.getJSONArray("repositories").length() == 0)
    succeed()
    model.chooseRepository("example/api")
    model.save()
    model.save()
    check(pending.size == 1)
    pending.removeAt(0).second(Result.failure(IllegalStateException("Save failed")))
    check(model.dirty && model.repository == "example/api" && !model.busy)
    model.load()
    check(pending.single().first.getString("installation_id") == "73")
    succeed()
    check(model.repository == "example/api")
    model.save()
    succeed()
    check(!model.dirty)
    model.chooseInstallation(null)
    model.save()
    check(pending.single().first.isNull("installation_id") && pending.single().first.isNull("default_repository"))
    succeed()
    model.load()
    val late = pending.removeAt(0)
    model.clear()
    late.second(Result.success(fixtures.execute(late.first)))
    check(model.catalog == null && model.repository == null)
}
