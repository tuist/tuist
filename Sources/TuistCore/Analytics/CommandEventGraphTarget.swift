import XcodeGraph

/// A simplified `GraphTarget` to store in `CommandEvent`. As this model gets stored on disk, we want to minimize the information
/// we end up storing.
public struct CommandEventGraphTarget: Codable, Hashable {
    public init(
        target: CommandEventTarget,
        project: CommandEventProject
    ) {
        self.target = target
        self.project = project
    }

    public init(
        _ graphTarget: GraphTarget
    ) {
        target = CommandEventTarget(graphTarget.target)
        project = CommandEventProject(graphTarget.project)
    }

    public let target: CommandEventTarget
    public let project: CommandEventProject
}

#if DEBUG
    extension CommandEventGraphTarget {
        public static func test(
            target: CommandEventTarget = .test(),
            project: CommandEventProject = .test()
        ) -> Self {
            Self(
                target: target,
                project: project
            )
        }
    }
#endif
