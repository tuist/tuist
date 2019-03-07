import Basic
import Foundation
import xcodeproj
@testable import TuistKit

extension GeneratedProject {
    static func test(path: AbsolutePath = AbsolutePath("/project.xcodeproj"),
                     targets: [String: PBXNativeTarget] = [:],
                     name: String = "project.xcodeproj") -> GeneratedProject {
        return GeneratedProject(path: path, targets: targets, name: name)
    }
}
