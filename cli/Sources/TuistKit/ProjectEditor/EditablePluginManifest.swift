import Foundation
import Path

/// A plugin which is loaded & editable as part of the `tuist edit` command.
struct EditablePluginManifest: Hashable {
    let name: String
    let path: AbsolutePath

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path
    }
}
