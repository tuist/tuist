import Foundation
import TSCBasic
import XcodeProj
@testable import TuistGenerator

extension GeneratedProject {
    static func test(
        pbxproj: PBXProj = .init(),
        path: AbsolutePath = AbsolutePath("/project.xcodeproj"),
        targets: [String: PBXNativeTarget] = [:],
        name: String = "project.xcodeproj"
    ) -> GeneratedProject {
        GeneratedProject(pbxproj: pbxproj, path: path, targets: targets, name: name)
    }
}
