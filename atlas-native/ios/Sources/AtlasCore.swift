import AtlasCoreFFI
import Foundation

struct AtlasSection: Identifiable {
    let id: String
    let title: String
    let description: String
    let url: URL
    let screen: String
    let group: String
    let shortcut: Bool
    let requiredScope: String

    func destination(on server: URL) -> URL {
        guard var destination = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let origin = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return url }
        destination.scheme = origin.scheme
        destination.host = origin.host
        destination.port = origin.port
        return destination.url ?? url
    }
}

struct AtlasGroup: Identifiable {
    let id: String
    let title: String
    let description: String
    let parent: String
    let placement: String
}

struct AtlasCatalog {
    let groups = AtlasCore.groups()
    let sections = AtlasCore.sections()

    var workspaceSections: [AtlasSection] {
        sections.filter { section in
            ["tasks", "accounts", "invoices", "time-off", "people"].contains(section.screen)
                && groups.contains { $0.id == section.group && $0.placement == "workspace" }
        }
    }
    var shortcuts: [AtlasSection] { workspaceSections.filter(\.shortcut) }

    func children(of parent: String? = nil) -> [AtlasGroup] {
        groups.filter { $0.parent == (parent ?? "") && $0.placement == "workspace" && hasNativeEntries($0.id) }
    }

    private func hasNativeEntries(_ group: String) -> Bool {
        workspaceSections.contains { $0.group == group }
            || groups.filter { $0.parent == group }.contains { hasNativeEntries($0.id) }
    }

    func entries(in group: String) -> [AtlasSection] { workspaceSections.filter { $0.group == group } }

    func breadcrumb(for section: AtlasSection) -> String {
        var current = groups.first { $0.id == section.group }
        var titles: [String] = []
        var visited: Set<String> = []
        while let group = current, visited.insert(group.id).inserted {
            titles.append(group.title)
            current = groups.first { $0.id == group.parent }
        }
        return titles.reversed().joined(separator: " › ")
    }

    func search(_ query: String) -> [AtlasSection] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        return workspaceSections.filter { section in
            let text = "\(section.title) \(section.description) \(breadcrumb(for: section))"
            return terms.allSatisfy { text.localizedStandardContains($0) }
        }
    }
}

enum AtlasCore {
    static func sections() -> [AtlasSection] {
        (0..<atlas_section_count()).compactMap { index in
            guard
                let title = field(section: index, id: 0),
                let description = field(section: index, id: 1),
                let destination = field(section: index, id: 2),
                let screen = field(section: index, id: 3),
                let key = field(section: index, id: 4),
                let group = field(section: index, id: 5),
                let shortcut = field(section: index, id: 6),
                let scope = field(section: index, id: 7),
                let url = URL(string: destination),
                url.scheme == "https", url.host == "atlas.tuist.dev"
            else { return nil }
            return AtlasSection(id: key, title: title, description: description, url: url, screen: screen,
                                group: group, shortcut: shortcut == "1", requiredScope: scope)
        }
    }

    static func groups() -> [AtlasGroup] {
        (0..<atlas_group_count()).compactMap { index in
            guard let title = groupField(group: index, id: 0), let description = groupField(group: index, id: 1),
                  let key = groupField(group: index, id: 2), let parent = groupField(group: index, id: 3),
                  let placement = groupField(group: index, id: 4) else { return nil }
            return AtlasGroup(id: key, title: title, description: description, parent: parent, placement: placement)
        }
    }

    static func field(section: Int32, id: Int32) -> String? {
        guard let pointer = atlas_section_field(section, id) else { return nil }
        return String(validatingCString: pointer)
    }

    static func groupField(group: Int32, id: Int32) -> String? {
        guard let pointer = atlas_group_field(group, id) else { return nil }
        return String(validatingCString: pointer)
    }
}
