import Foundation
import TuistServer

struct ProjectPickerSection: Identifiable {
    let id: String
    let title: String
    let projects: [ServerProject]
    var isRecent: Bool { id == "recent" }

    static func make(projects: [ServerProject], recentProjects: [ServerProject], search: String) -> [Self] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = projects.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }
        let availableHandles = Set(matches.map(\.fullName))
        var seen = Set<String>()
        let recents = query.isEmpty ? recentProjects.filter {
            availableHandles.contains($0.fullName) && seen.insert($0.fullName).inserted
        } : []
        let remaining = matches.filter { seen.insert($0.fullName).inserted }
        let groups = Dictionary(grouping: remaining) { String($0.fullName.split(separator: "/").first ?? "") }
        return (recents.isEmpty ? [] : [Self(id: "recent", title: "Recent Projects", projects: recents)])
            + groups.keys.sorted().map { organization in
                Self(
                    id: "organization:\(organization)",
                    title: organization,
                    projects: groups[organization, default: []].sorted { $0.fullName < $1.fullName }
                )
            }
    }
}
