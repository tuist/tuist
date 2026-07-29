import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

public enum CacheWarmForeignBuildOutputValidatorError: LocalizedError, Equatable {
    case unsupported(scratchDirectory: AbsolutePath, targetNames: [String])
    case unsupportedTargetScripts(scratchDirectory: AbsolutePath, targetNames: [String])

    public var errorDescription: String? {
        switch self {
        case let .unsupported(scratchDirectory, targetNames):
            return """
            The cache warm scratch directory at \(scratchDirectory
                .pathString) cannot be used with foreign build targets: \(targetNames.joined(separator: ", ")). \
            Foreign build scripts control their output locations, so Tuist cannot guarantee that every build output stays inside the scratch directory.
            """
        case let .unsupportedTargetScripts(scratchDirectory, targetNames):
            return """
            The cache warm scratch directory at \(scratchDirectory
                .pathString) cannot be used with targets that contain build scripts: \(targetNames.joined(separator: ", ")). \
            Build scripts can write outside their declared output paths, so Tuist cannot guarantee that every build output stays inside the scratch directory.
            """
        }
    }
}

@Mockable
public protocol CacheWarmForeignBuildOutputValidating {
    func validate(
        targets: [GraphTarget],
        scratchDirectory: CacheWarmScratchDirectory
    ) throws
}

public struct CacheWarmForeignBuildOutputValidator: CacheWarmForeignBuildOutputValidating {
    public init() {}

    public func validate(
        targets: [GraphTarget],
        scratchDirectory: CacheWarmScratchDirectory
    ) throws {
        guard case let .callerOwned(path) = scratchDirectory else {
            return
        }

        let foreignBuildTargetNames = targets
            .filter { $0.target.foreignBuild != nil }
            .map(\.target.name)
            .sorted()
        if !foreignBuildTargetNames.isEmpty {
            throw CacheWarmForeignBuildOutputValidatorError.unsupported(
                scratchDirectory: path,
                targetNames: foreignBuildTargetNames
            )
        }

        let targetScriptNames = targets
            .filter { $0.target.foreignBuild == nil && !$0.target.scripts.isEmpty }
            .map(\.target.name)
            .sorted()
        guard !targetScriptNames.isEmpty else {
            return
        }

        throw CacheWarmForeignBuildOutputValidatorError.unsupportedTargetScripts(
            scratchDirectory: path,
            targetNames: targetScriptNames
        )
    }
}
