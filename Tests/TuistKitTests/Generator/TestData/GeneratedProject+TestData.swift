import Basic
import Foundation
@testable import TuistKit
import xcodeproj

extension GeneratedProject {
    static func test(path: AbsolutePath = AbsolutePath("/project.xcodeproj"),
                     targets: [String: PBXNativeTarget] = [:]) -> GeneratedProject {
        return GeneratedProject(path: path, targets: targets)
    }
}
