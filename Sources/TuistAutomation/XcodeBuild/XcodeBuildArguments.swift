import Foundation
import Path
import XcodeGraph

public struct XcodeBuildArguments: Equatable {
    public struct Destination: Equatable {
        public let name: String?
        public let platform: String?
        public let id: String?
        public let os: Version?

        public init(
            name: String?,
            platform: String?,
            id: String?,
            os: Version?
        ) {
            self.name = name
            self.platform = platform
            self.id = id
            self.os = os
        }
    }

    public let derivedDataPath: AbsolutePath?
    public let destination: Destination?
    public let projectPath: AbsolutePath?
    public let workspacePath: AbsolutePath?

    public init(
        derivedDataPath: AbsolutePath?,
        destination: Destination?,
        projectPath: AbsolutePath?,
        workspacePath: AbsolutePath?
    ) {
        self.derivedDataPath = derivedDataPath
        self.destination = destination
        self.projectPath = projectPath
        self.workspacePath = workspacePath
    }
}

extension XcodeBuildArguments {
    public static func test(
        derivedDataPath: AbsolutePath? = nil,
        destination: Destination? = nil,
        projectPath: AbsolutePath? = nil,
        workspacePath: AbsolutePath? = nil
    ) -> XcodeBuildArguments {
        XcodeBuildArguments(
            derivedDataPath: derivedDataPath,
            destination: destination,
            projectPath: projectPath,
            workspacePath: workspacePath
        )
    }
}
