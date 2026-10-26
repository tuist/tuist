package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasCore
import dev.tuist.atlas.AtlasWorkspaceModel

internal fun checkWorkspaceModel() {
    val core = AtlasCore()
    val model = AtlasWorkspaceModel(core.groups(), core.sections())
    check(
        model.children().map { it.id } ==
            listOf("overview", "commercial", "people"),
    )
    check(model.shortcuts.map { it.id } == listOf("tasks", "time-off"))
    check(model.sections.none { it.group == "settings" })
    check(model.sections.all { it.screen in listOf("tasks", "accounts", "invoices", "time-off", "people") })
    check(!model.back())
    model.open("commercial")
    check(model.children().map { it.id } == listOf("sales", "finance"))
    model.open("finance")
    model.search("  finance  ")
    check(model.results().map { it.screen } == listOf("invoices"))
    check(model.breadcrumb(model.results().single()) == "Commercial › Finance")
    check(model.back() && model.groupId == "finance" && model.query.isEmpty())
    check(model.back() && model.groupId == "commercial")
    check(model.back() && model.groupId == null)
    model.open("settings")
    model.open("unknown")
    check(model.groupId == null)
    model.search("does-not-exist")
    check(model.results().isEmpty())
    model.search("engineering")
    check(model.results().isEmpty())
    val restored = AtlasWorkspaceModel(core.groups(), core.sections(), "sales")
    check(restored.groupId == "sales" && restored.back() && restored.groupId == "commercial")
    check(AtlasWorkspaceModel(core.groups(), core.sections(), "hardware").groupId == null)
    check(AtlasWorkspaceModel(core.groups(), core.sections(), "settings").groupId == null)
    check(AtlasWorkspaceModel(core.groups(), core.sections(), "not-a-group").groupId == null)
}
