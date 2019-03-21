import Basic
import Foundation
@testable import TuistKit

extension Workspace {
    static func test(name: String = "test",
                     projects: [AbsolutePath] = [],
                     additionalFiles: [Workspace.Element] = []) -> Workspace {
        return Workspace(name: name,
                         projects: projects,
                         additionalFiles: additionalFiles)
    }
}
