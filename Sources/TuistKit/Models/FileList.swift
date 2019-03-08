import Basic
import Foundation
import TuistCore

class FileList: JSONMappable, Equatable {
    // MARK: - Attributes

    let globs: [String]

    // MARK: - Init

    required init(json: JSON) throws {
        if let globs: [String] = try? json.get("globs") {
            self.globs = globs
        } else {
            globs = []
        }
    }

    static func == (lhs: FileList, rhs: FileList) -> Bool {
        return lhs.globs == rhs.globs
    }
}
