import Foundation
import TSCBasic

/// A plugin which is loaded & editable as part of the `tuist edit` command.
struct EditablePluginManifest {
    let name: String
    let path: AbsolutePath
}

extension EditablePluginManifest: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path
    }
}
