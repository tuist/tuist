import Foundation

public struct XCActivityTarget: Equatable, Hashable {
    public let name: String
    /// Name of the target's project.
    public let project: String
    /// The build duration of the target in milliseconds. This is usually longer than compile duration as it includes extra steps
    /// such as custom build phases.
    public let buildDuration: Int
    /// Compilation duration in milliseconds. This can be 0 if the target did not contain any sources to compile (such as
    /// bundles).
    public let compilationDuration: Int
    /// The status of the build.
    public let status: XCActivityBuildStatus
}

#if DEBUG
    extension XCActivityTarget {
        public static func test(
            name: String = "Target",
            project: String = "Project",
            buildDuration: Int = 100,
            compilationDuration: Int = 100,
            status: XCActivityBuildStatus = .success
        ) -> XCActivityTarget {
            XCActivityTarget(
                name: name,
                project: project,
                buildDuration: buildDuration,
                compilationDuration: compilationDuration,
                status: status
            )
        }
    }
#endif
