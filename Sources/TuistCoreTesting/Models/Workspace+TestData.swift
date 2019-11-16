import Basic
import Foundation
@testable import TuistCore

public extension Workspace {
    static func test(name: String = "test",
                     projects: [AbsolutePath] = [],
                     additionalFiles: [FileElement] = []) -> Workspace {
        return Workspace(name: name,
                         projects: projects,
                         additionalFiles: additionalFiles)
    }
}
