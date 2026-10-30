package dev.tuist.atlas

class AtlasWorkspaceModel(
    groups: List<AtlasGroup>,
    sections: List<AtlasSection>,
    restoredGroup: String? = null,
) {
    val sections =
        sections.filter { section ->
            section.screen in listOf("tasks", "accounts", "invoices", "time-off", "people", "automation") &&
                groups.any { it.id == section.group && it.placement == "workspace" }
        }
    val groups =
        groups.filter { group ->
            this.sections.any { section ->
                var current = section.group
                val visited = mutableSetOf<String>()
                while (current.isNotEmpty() && visited.add(current)) {
                    if (current == group.id) return@any true
                    current = groups.firstOrNull { it.id == current }?.parent.orEmpty()
                }
                false
            }
        }
    val shortcuts get() = sections.filter { it.shortcut }
    var groupId: String? = restoredGroup?.takeIf { id -> this.groups.any { it.id == id && it.placement == "workspace" } }
        private set
    var query: String = ""
        private set
    var listener: (() -> Unit)? = null
    val group get() = groups.firstOrNull { it.id == groupId }
    val canBack get() = query.isNotEmpty() || groupId != null

    fun children(): List<AtlasGroup> = groups.filter { it.parent == (groupId ?: "") && it.placement == "workspace" }

    fun entries(): List<AtlasSection> = sections.filter { it.group == groupId }

    fun open(id: String) {
        if (groups.none { it.id == id && it.placement == "workspace" }) return
        groupId = id
        query = ""
        listener?.invoke()
    }

    fun search(value: String) {
        if (value == query) return
        query = value
        listener?.invoke()
    }

    fun back(): Boolean {
        if (!canBack) return false
        if (query.isNotEmpty()) query = "" else groupId = group?.parent?.ifEmpty { null }
        listener?.invoke()
        return true
    }

    fun breadcrumb(section: AtlasSection): String {
        var current = groups.firstOrNull { it.id == section.group }
        val titles = mutableListOf<String>()
        val visited = mutableSetOf<String>()
        while (current != null && visited.add(current.id)) {
            titles.add(current.title)
            val parent = current.parent
            current = groups.firstOrNull { it.id == parent }
        }
        return titles.reversed().joinToString(" › ")
    }

    fun results(): List<AtlasSection> {
        val terms =
            query
                .trim()
                .lowercase()
                .split(Regex("\\s+"))
                .filter { it.isNotEmpty() }
        if (terms.isEmpty()) return emptyList()
        return sections.filter { section ->
            val text = "${section.title} ${section.description} ${breadcrumb(section)}".lowercase()
            terms.all { text.contains(it) }
        }
    }
}
