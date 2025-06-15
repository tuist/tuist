import Foundation
import Path

public enum XCActivityBuildFileType: Hashable, Equatable {
    case swift, c
}

public struct XCActivityBuildFile: Hashable, Equatable {
    public let type: XCActivityBuildFileType
    public let target: String
    public let project: String
    public let path: RelativePath
    /// Compilation duration in milliseconds
    public let compilationDuration: Int
}

#if DEBUG
    extension XCActivityBuildFile {
        public static func test(
            type: XCActivityBuildFileType = .swift,
            target: String = "Target",
            project: String = "Project",
            // swiftlint:disable:next force_try
            path: RelativePath = try! RelativePath(validating: "Path"),
            compilationDuration: Int = 100
        ) -> XCActivityBuildFile {
            XCActivityBuildFile(
                type: type,
                target: target,
                project: project,
                path: path,
                compilationDuration: compilationDuration
            )
        }
    }
#endif
