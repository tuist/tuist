import Basic
import Foundation
import TuistCore

public class FileList: JSONMappable, Equatable {
    // MARK: - Attributes

    public let globs: [String]

    // MARK: - Init

    public required init(json: JSON) throws {
        if let globs: [String] = try? json.get("globs") {
            self.globs = globs
        } else {
            globs = []
        }
    }

    public static func == (lhs: FileList, rhs: FileList) -> Bool {
        return lhs.globs == rhs.globs
    }
}
