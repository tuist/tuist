import Foundation
import TSCBasic
import TuistSupport

enum BinaryLocatorError: FatalError, Equatable {
    case xcbeautifyNotFound

    var description: String {
        switch self {
        case .xcbeautifyNotFound:
            return "Couldn't find the xcbeautify binary."
        }
    }

    var type: ErrorType {
        switch self {
        case .xcbeautifyNotFound:
            return .bug
        }
    }
}

/// Protocol that defines the interface to locate the tuist binary in the environment.
public protocol BinaryLocating {
    /// Returns the command to run xcbeautify.
    func xcbeautifyExecutable() throws -> SwiftPackageExecutable
}

public struct SwiftPackageExecutable {
    public let compilation: [String]?
    public let execution: [String]
}

public final class BinaryLocator: BinaryLocating {
    public init() {}

    public func xcbeautifyExecutable() throws -> SwiftPackageExecutable {
        try xcbeautifyExecutable(environment: Environment.shared)
    }

    public func xcbeautifyExecutable(environment: Environmenting) throws -> SwiftPackageExecutable {
        var bundlePath = try AbsolutePath(validating: Bundle(for: BinaryLocator.self).bundleURL.path)
        let candidatebinariesPath = [
            bundlePath,
            bundlePath.parentDirectory,
            bundlePath.appending(try RelativePath(validating: "vendor")),
            /**
                == Homebrew directory structure ==
                x.y.z/
                bin/
                    tuist
                share/
                    tuist/
                        vendor
                */
            bundlePath.parentDirectory.appending(try RelativePath(validating: "share/tuist")),
        ]
        let candidates = candidatebinariesPath.map { path in
            path.appending(components: "xcbeautify")
        }
        if let existingPath = candidates.first(where: FileHandler.shared.exists) {
            return SwiftPackageExecutable(compilation: nil, execution: [existingPath.pathString])
        }

        bundlePath = try AbsolutePath(validating: #file.replacingOccurrences(of: "file://", with: ""))
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .appending(try RelativePath(validating: "vendor"))

        if let xcbeautifyBinaryPath = Environment.shared
            .tuistConfigVariables[Constants.EnvironmentVariables.xcbeautifyBinaryPath]
        {
            return SwiftPackageExecutable(compilation: nil, execution: [xcbeautifyBinaryPath])
        } else if FileHandler.shared.exists(bundlePath) {
            let compilationCommand = [
                "/usr/bin/xcrun", "swift", "build", "--configuration", "debug", "--package-path", bundlePath.pathString,
                "--product", "xcbeautify",
            ]

            var executionCommand = [
                // swiftlint:disable:next force_try
                bundlePath.appending(try! RelativePath(validating: ".build/debug/xcbeautify")).pathString,
            ]
            if let renderer = renderer(environment: environment) {
                executionCommand.append(contentsOf: ["--renderer", "github-actions"])
            }

            return SwiftPackageExecutable(compilation: compilationCommand, execution: executionCommand)
        } else {
            throw BinaryLocatorError.xcbeautifyNotFound
        }
    }

    private func renderer(environment: Environmenting) -> String? {
        if environment.isGitHubActions {
            return "github-actions"
        }
        return nil
    }
}
