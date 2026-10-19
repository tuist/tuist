package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasCore
import dev.tuist.atlas.AtlasWorkspaceModel

internal fun checkWorkspaceModel() {
    val core = AtlasCore()
    val model = AtlasWorkspaceModel(core.groups(), core.sections())
    check(
        model.children().map { it.id } ==
            listOf("overview", "commercial", "outbound", "engineering", "people", "operations", "library", "admin"),
    )
    check(model.shortcuts.map { it.id } == listOf("tasks", "time-off"))
    check(model.sections.none { it.group == "settings" })
    check(!model.back())
    model.open("commercial")
    check(model.children().map { it.id } == listOf("sales", "finance", "gtm"))
    model.open("finance")
    model.search("  VENDOR finance  ")
    check(model.results().map { it.id } == listOf("vendors"))
    check(model.breadcrumb(model.results().single()) == "Commercial › Finance")
    check(
        model
            .results()
            .single()
            .destination("https://atlas.example.org:4443")
            .toString() ==
            "https://atlas.example.org:4443/commercial/finance/vendors",
    )
    check(model.back() && model.groupId == "finance" && model.query.isEmpty())
    check(model.back() && model.groupId == "commercial")
    check(model.back() && model.groupId == null)
    model.open("settings")
    model.open("unknown")
    check(model.groupId == null)
    model.search("does-not-exist")
    check(model.results().isEmpty())
    model.search("engineering")
    check(model.results().size == 5)
    val restored = AtlasWorkspaceModel(core.groups(), core.sections(), "hardware")
    check(restored.groupId == "hardware" && restored.back() && restored.groupId == "operations")
    check(AtlasWorkspaceModel(core.groups(), core.sections(), "settings").groupId == null)
    check(AtlasWorkspaceModel(core.groups(), core.sections(), "not-a-group").groupId == null)
}
