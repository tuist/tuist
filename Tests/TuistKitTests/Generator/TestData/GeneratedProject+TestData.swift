import Basic
import Foundation
import xcodeproj
@testable import TuistKit

extension GeneratedProject {
    static func test(path: AbsolutePath = AbsolutePath("/project.xcodeproj"),
                     targets: [String: PBXNativeTarget] = [:]) -> GeneratedProject {
        return GeneratedProject(path: path, targets: targets)
    }
}
