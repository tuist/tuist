import Basic
import Foundation
import xcodeproj
import xpmcore

/// Headers
class Headers: GraphJSONInitiatable, Equatable {

    // MARK: - Attributes

    let `public`: [AbsolutePath]
    let `private`: [AbsolutePath]
    let project: [AbsolutePath]

    // MARK: - Init

    required init(json: JSON, projectPath: AbsolutePath, fileHandler _: FileHandling) throws {
        if let `public`: String = try? json.get("public") {
            self.public = projectPath.glob(`public`)
        } else {
            `public` = []
        }

        if let `private`: String = try? json.get("private") {
            self.private = projectPath.glob(`private`)
        } else {
            `private` = []
        }

        if let project: String = try? json.get("project") {
            self.project = projectPath.glob(project)
        } else {
            project = []
        }
    }

    // MARK: - Equatable

    static func == (lhs: Headers, rhs: Headers) -> Bool {
        return lhs.public == rhs.public &&
            lhs.private == rhs.private &&
            lhs.project == rhs.project
    }
}
