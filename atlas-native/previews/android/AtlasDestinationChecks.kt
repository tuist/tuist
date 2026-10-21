package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasBusinessModel
import dev.tuist.atlas.AtlasCore
import dev.tuist.atlas.AtlasDestination
import dev.tuist.atlas.AtlasDestinationRouter
import dev.tuist.atlas.AuthFailure
import org.json.JSONObject

private const val RECORD = "0f8fad5b-d9cb-469f-a165-70867728950e"
private const val HOSTED = "https://atlas.tuist.dev/"

internal fun checkDestinations() {
    val capabilities = AtlasCore().destinations()
    check(capabilities.map { it.screen } == listOf("tasks", "accounts", "invoices", "time-off", "people", "profile"))
    check(capabilities.filter { it.records }.map { it.screen } == listOf("tasks", "accounts", "invoices"))

    fun parse(link: String) = AtlasDestination.parse(link, capabilities)

    val accepted =
        mapOf(
            "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.tuist.dev" to AtlasDestination("tasks"),
            "dev.tuist.atlas://navigate/tasks/$RECORD?server=https%3A%2F%2Fatlas.tuist.dev%2F" to AtlasDestination("tasks", RECORD),
            "dev.tuist.atlas://navigate/accounts/$RECORD?server=https://atlas.tuist.dev" to AtlasDestination("accounts", RECORD),
            "dev.tuist.atlas://navigate/invoices/$RECORD?server=https%3A%2F%2FATLAS.Tuist.DEV%3A443%2F" to
                AtlasDestination("invoices", RECORD),
            "DEV.TUIST.ATLAS://NAVIGATE/time-off?server=HTTPS://atlas.tuist.dev" to AtlasDestination("time-off"),
            "dev.tuist.atlas://navigate/people?server=https://atlas.tuist.dev/" to AtlasDestination("people"),
            "dev.tuist.atlas://navigate/profile?server=https://atlas.tuist.dev" to AtlasDestination("profile"),
        )
    accepted.forEach { (link, destination) ->
        check(parse(link) == AtlasDestination.Link(destination, HOSTED)) { "Expected to accept $link" }
        check(AtlasDestination.isNavigation(link))
    }
    check(parse("dev.tuist.atlas://navigate/tasks?server=https://xn--tlas-xqa.example.org")?.server == "https://xn--tlas-xqa.example.org/")

    val server = "?server=https://atlas.tuist.dev"
    val rejected =
        listOf(
            "dev.tuist.atlas://navigate/tasks",
            "dev.tuist.atlas://navigate/tasks?",
            "dev.tuist.atlas://navigate/tasks?server=",
            "dev.tuist.atlas://navigate/tasks$server&server=https://atlas.example.org",
            "dev.tuist.atlas://navigate/tasks$server&tab=accounts",
            "dev.tuist.atlas://navigate/tasks?tab=accounts&server=https://atlas.tuist.dev",
            "dev.tuist.atlas://navigate/tasks$server#details",
            "dev.tuist.atlas://navigate/tasks#x$server",
            "dev.tuist.atlas://navigate/tasks/$server",
            "dev.tuist.atlas://navigate/tasks/${RECORD.uppercase()}$server",
            "dev.tuist.atlas://navigate/tasks/{$RECORD}$server",
            "dev.tuist.atlas://navigate/tasks/${RECORD.replace("-", "")}$server",
            "dev.tuist.atlas://navigate/tasks/1-1-1-1-1$server",
            "dev.tuist.atlas://navigate/tasks/$RECORD/edit$server",
            "dev.tuist.atlas://navigate/tasks%2F$RECORD$server",
            "dev.tuist.atlas://navigate/%74asks$server",
            "dev.tuist.atlas://navigate/Tasks$server",
            "dev.tuist.atlas://navigate/time-off/$RECORD$server",
            "dev.tuist.atlas://navigate/profile/$RECORD$server",
            "dev.tuist.atlas://navigate/notes$server",
            "dev.tuist.atlas://navigate/browser$server",
            "dev.tuist.atlas://navigate/ai-providers$server",
            "dev.tuist.atlas://navigate/$server",
            "dev.tuist.atlas://navigate//tasks$server",
            "dev.tuist.atlas://navigate$server",
            "dev.tuist.atlas://oauth-callback/tasks$server",
            "dev.tuist.atlas://user@navigate/tasks$server",
            "dev.tuist.atlas://navigate:80/tasks$server",
            "https://atlas.tuist.dev/tasks$server",
            "dev.tuist.atlas://navigate/tasks?server=http://atlas.tuist.dev",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas.tuist.dev:0",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas.tuist.dev:65536",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas.tuist.dev:+443",
            "dev.tuist.atlas://navigate/tasks?server=https://user@atlas.tuist.dev",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas.tuist.dev/path",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas.tuist.dev//",
            "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.tuist.dev%3Fq",
            "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.tuist.dev%23",
            "dev.tuist.atlas://navigate/tasks?server=https%253A%252F%252Fatlas.tuist.dev",
            "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.tuist.dev%2",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas+tuist.dev",
            "dev.tuist.atlas://navigate/tasks?server=https://%C3%A1tlas.example.org",
            "dev.tuist.atlas://navigate/tasks?server=https://[::g]",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas..tuist.dev",
            "dev.tuist.atlas://navigate/tasks?server=https://-atlas.tuist.dev",
            "dev.tuist.atlas://navigate/tasks?server=https://",
            "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.tuist.dev%0A",
            "dev.tuist.atlas://navigate/tasks?server=https://atlas.tuist.dev" + "a".repeat(2048),
        )
    rejected.forEach { check(parse(it) == null) { "Expected to reject $it" } }
    check(!AtlasDestination.isNavigation("dev.tuist.atlas://oauth-callback?code=x&state=y"))
    check(!AtlasDestination.isNavigation("dev.tuist.atlas://navigator/tasks"))
    check(AtlasDestination.isNavigation("dev.tuist.atlas://navigate"))

    check(AtlasDestination.canonicalServer("https://atlas.tuist.dev/") == HOSTED)
    check(AtlasDestination.canonicalServer("https://Atlas.Example.ORG:443") == "https://atlas.example.org/")
    check(AtlasDestination.canonicalServer("https://atlas.example.org:8443/") == "https://atlas.example.org:8443/")
    // Port spellings Foundation also normalizes; explicit invalid ports are rejected.
    check(AtlasDestination.canonicalServer("https://atlas.example.org:") == "https://atlas.example.org/")
    check(AtlasDestination.canonicalServer("https://atlas.example.org:0443") == "https://atlas.example.org/")
    check(AtlasDestination.canonicalServer("https://atlas.example.org:0") == null)
    check(AtlasDestination.canonicalServer("https://atlas.example.org:65536") == null)
    // IPv6 literals are validated by java.net.URI; hostnames follow its RFC 2396 rules without DNS lookups.
    check(AtlasDestination.canonicalServer("https://[::1]") == "https://[::1]/")
    check(AtlasDestination.canonicalServer("https://[FD00::A]:8443/") == "https://[fd00::a]:8443/")
    check(AtlasDestination.canonicalServer("https://[::g]") == null)
    check(AtlasDestination.canonicalServer("https://[::1") == null)
    check(AtlasDestination.canonicalServer("https://127.0.0.1") == "https://127.0.0.1/")
    // Preserve server origins accepted by Rust; no DNS lookups are needed to compare them.
    check(AtlasDestination.canonicalServer("https://atlas_internal.example.org") == "https://atlas_internal.example.org/")
    check(AtlasDestination.canonicalServer("https://atlas+internal.example.org") == null)
    // Punycode hosts stay ASCII; Unicode hosts are rejected before canonicalization.
    check(AtlasDestination.canonicalServer("https://xn--tlas-xqa.example.org:4443") == "https://xn--tlas-xqa.example.org:4443/")
    check(AtlasDestination.canonicalServer("https://éxample.org") == null)
    check(parse("dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2F%5B%3A%3A1%5D%3A8443")?.server == "https://[::1]:8443/")
    check(parse("dev.tuist.atlas://navigate/tasks?server=https://[::1]:8443/")?.server == "https://[::1]:8443/")
    check(parse("dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.tuist.dev%3A8443")?.server == "https://atlas.tuist.dev:8443/")

    checkIOSParity(capabilities)

    checkDestinationRouter()
    checkRecordLinks()
}

private fun checkDestinationRouter() {
    val tasks = AtlasDestination.Link(AtlasDestination("tasks"), HOSTED)
    val record = AtlasDestination.Link(AtlasDestination("accounts", RECORD), HOSTED)
    val router = AtlasDestinationRouter()

    // Cold link: held while restoring or signing in, latest wins, opened once.
    router.receive(tasks)
    check(router.resolve(null) == AtlasDestinationRouter.Outcome.None && router.pending == tasks)
    router.receive(record)
    check(router.resolve(HOSTED) == AtlasDestinationRouter.Outcome.Open(record.destination))
    check(router.pending == null && router.resolve(HOSTED) == AtlasDestinationRouter.Outcome.None)

    // The authenticated server is compared after normalization; another server never switches sessions.
    router.receive(tasks)
    check(router.resolve("https://ATLAS.tuist.dev:443") == AtlasDestinationRouter.Outcome.Open(tasks.destination))
    router.receive(tasks)
    check(router.resolve("https://atlas.example.org/") == AtlasDestinationRouter.Outcome.WrongServer && router.pending == null)
    router.receive(tasks)
    check(router.resolve("https://atlas.tuist.dev:8443/") == AtlasDestinationRouter.Outcome.WrongServer)
    val custom = AtlasDestination.Link(AtlasDestination("tasks"), "https://atlas.example.org:4443/")
    router.receive(custom)
    check(router.resolve("https://atlas.example.org:4443") == AtlasDestinationRouter.Outcome.Open(custom.destination))
    router.receive(custom)
    check(router.resolve("https://atlas.example.org/") == AtlasDestinationRouter.Outcome.WrongServer)

    // A link received during a session is discarded when that session ends (sign-out or rejected credentials).
    router.receive(tasks)
    check(router.resolve(null) == AtlasDestinationRouter.Outcome.None && router.pending == null)
    router.receive(tasks)
    check(router.resolve(null) == AtlasDestinationRouter.Outcome.None && router.pending == tasks)
    router.reset()
    check(router.pending == null)
}

private fun checkRecordLinks() {
    val fixtures = AtlasBusinessFixtures()
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasBusinessModel("tasks") { action, done -> pending.add(action to done) }

    fun succeed() {
        val (action, done) = pending.removeAt(0)
        done(Result.success(fixtures.execute(action)))
    }

    // Direct ID loading never searches or pages, and replaces a list read in flight.
    model.load()
    val staleList = pending.removeAt(0)
    model.open("task-3")
    check(model.placeholder && model.selected?.id == "task-3" && model.selected?.canEdit == false && model.busy)
    check(
        pending.single().first.toString() ==
            JSONObject()
                .put("action", "show")
                .put("id", "task-3")
                .put("resource", "tasks")
                .toString(),
    )
    model.edit(model.selected)
    model.delete(model.selected!!)
    model.complete(model.selected!!)
    check(model.draft == null && pending.size == 1)
    staleList.second(Result.success(fixtures.execute(staleList.first)))
    check(model.items.isEmpty() && !model.loaded && model.placeholder)
    succeed()
    check(!model.placeholder && model.selected?.get("title") == "Send follow-up" && model.recordFailure == null)

    // The resolved record then loads the first list page for edit options; editing waits for it.
    check(pending.single().first.getString("action") == "list" && !model.loaded && model.selected?.canEdit == true)
    model.edit(model.selected)
    check(model.draft == null)
    succeed()
    check(model.loaded && model.selected?.id == "task-3" && model.options.getValue("users").isNotEmpty())
    model.edit(model.selected)
    check(model.draft?.id == "task-3")
    model.back()
    check(model.back() && model.selected == null && pending.isEmpty())

    // Back during that options read returns to the list and reloads it instead of leaving it empty.
    val reopened = AtlasBusinessModel("tasks") { action, done -> pending.add(action to done) }
    reopened.open("task-3")
    succeed()
    val optionsRead = pending.removeAt(0)
    check(reopened.back() && reopened.selected == null && pending.single().first.getString("action") == "list")
    optionsRead.second(Result.success(fixtures.execute(optionsRead.first)))
    succeed()
    check(reopened.loaded && reopened.items.isNotEmpty())

    // The newest link wins; a late response for an older one is ignored.
    model.open("task-1")
    val older = pending.removeAt(0)
    model.open("task-2")
    succeed()
    older.second(Result.success(fixtures.execute(older.first)))
    check(model.selected?.id == "task-2" && !model.placeholder && !model.busy)

    // A deleted or unknown record stays on a read-only failure screen with Back and Retry.
    model.open(RECORD)
    pending.removeAt(0).second(Result.failure(AuthFailure("unavailable", "This item is no longer available. Refresh the list.")))
    check(model.placeholder && model.recordFailure == "unavailable" && model.selected?.id == RECORD && model.error != null)
    check(model.selected?.canEdit == false && model.selected?.canDelete == false)

    // Transient failures and malformed responses keep the ID for retry.
    model.open(RECORD)
    pending.removeAt(0).second(Result.failure(IllegalStateException("Could not complete the request. Try again.")))
    check(model.recordFailure == "failed" && model.error == "Could not complete the request. Try again.")
    model.open(RECORD)
    pending.removeAt(0).second(Result.success(JSONObject().put("item", JSONObject().put("id", "task-1"))))
    check(model.recordFailure == "invalid" && model.placeholder && model.error == "Atlas returned an invalid response. Try again.")
    model.open("task-1")
    pending
        .removeAt(
            0,
        ).second(Result.success(fixtures.execute(JSONObject().put("action", "show").put("id", "task-1").put("resource", "tasks"))))
    check(!model.placeholder && model.recordFailure == null && model.error == null)

    // Forbidden records revoke cached rows; Back then reloads the list rather than showing stale data.
    model.open(RECORD)
    pending.removeAt(0).second(Result.failure(AuthFailure("forbidden", "Your Atlas role does not allow this action.")))
    check(model.recordFailure == "forbidden" && model.items.isEmpty() && !model.loaded && model.selected?.id == RECORD)
    check(model.back() && pending.single().first.getString("action") == "list")
    succeed()

    // A screen link shows the list, preserving search and filters.
    model.load(search = "follow-up")
    succeed()
    model.open("task-3")
    succeed()
    model.showList()
    check(model.selected == null && model.query == "follow-up" && pending.isEmpty())

    // Links never replace a draft or an in-flight save.
    model.edit()
    model.open("task-1")
    model.showList()
    check(model.draft != null && model.selected == null && pending.isEmpty())
    model.back()

    // A signed-out session ignores late record responses.
    model.open("task-1")
    val late = pending.removeAt(0)
    model.clear()
    late.second(Result.success(fixtures.execute(late.first)))
    check(model.selected == null && !model.placeholder)
}

// Mirrors ios/Tests/AtlasNavigationTests.swift so both parsers accept and reject the same links.
private fun checkIOSParity(capabilities: List<dev.tuist.atlas.AtlasDestinationCapability>) {
    val record = "123e4567-e89b-12d3-a456-426614174000"
    val origin = "https://atlas.example.org/"
    val suffix = "?server=https%3A%2F%2Fatlas.example.org"
    val prefix = "dev.tuist.atlas://navigate/"

    fun parse(link: String) = AtlasDestination.parse(link, capabilities)

    capabilities.forEach { capability ->
        check(parse(prefix + capability.screen + suffix) == AtlasDestination.Link(AtlasDestination(capability.screen), origin))
        val withRecord = parse(prefix + capability.screen + "/" + record + suffix)
        check((withRecord != null) == capability.records)
        if (withRecord != null) check(withRecord == AtlasDestination.Link(AtlasDestination(capability.screen, record), origin))
    }
    val invalid =
        listOf(
            "tasks/",
            "tasks//$record",
            "tasks/$record/edit",
            "tasks/not-a-uuid",
            "tasks/1-1-1-1-1",
            "tasks/123E4567-E89B-12D3-A456-426614174000",
            "people/$record",
            "time-off/$record",
            "profile/$record",
            "browser",
            "notes",
            "ai-providers",
            "../tasks",
            "%74asks",
            "tasks/%2e%2e",
        ).map { prefix + it + suffix } +
            listOf(
                prefix + "tasks",
                prefix + "tasks" + suffix + "&server=https://atlas.example.org",
                prefix + "tasks" + suffix + "&action=delete",
                prefix + "tasks" + suffix + "#fragment",
                "dev.tuist.atlas://user@navigate/tasks$suffix",
                "dev.tuist.atlas://navigate:443/tasks$suffix",
                "https://navigate/tasks$suffix",
                "dev.tuist.atlas://oauth-callback/tasks$suffix",
                prefix + "tasks?server=http://atlas.example.org",
                prefix + "tasks?server=https://user@atlas.example.org",
                prefix + "tasks?server=https://atlas.example.org/other",
                prefix + "tasks?server=https://atlas.example.org%3Fx=1",
                prefix + "tasks?server=https://atlas.example.org%23fragment",
                prefix + "tasks?server=https://atlas.example.org:0",
                prefix + "tasks?server=https://éxample.org",
                prefix + "tasks?server=https://atlas+example.org",
            )
    invalid.forEach { check(parse(it) == null) { "Accepted: $it" } }

    // bindsToCanonicalHTTPSOrigin
    val canonical = AtlasDestination.canonicalServer("https://ATLAS.example.org:443/")
    check(canonical == origin && AtlasDestination.canonicalServer("https://atlas.example.org") == canonical)
    check(AtlasDestination.canonicalServer("https://other.example.org") != canonical)
    check(AtlasDestination.canonicalServer("https://atlas.example.org:4443") != canonical)
    check(AtlasDestination.canonicalServer("http://atlas.example.org") == null)
    check(
        AtlasDestination.canonicalServer("https://atlas.example.org:4443") ==
            AtlasDestination.canonicalServer("https://atlas.example.org:4443/"),
    )
    val ipv6 = parse(prefix + "tasks?server=https%3A%2F%2F%5B%3A%3A1%5D%3A4443")
    check(ipv6?.server == "https://[::1]:4443/" && ipv6.server == AtlasDestination.canonicalServer("https://[::1]:4443/"))
}
