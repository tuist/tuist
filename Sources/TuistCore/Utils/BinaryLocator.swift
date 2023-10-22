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
    func xcbeautifyCommand() throws -> [String]
}

public final class BinaryLocator: BinaryLocating {
    public init() {}

    public func xcbeautifyCommand() throws -> [String] {
        var bundlePath = try AbsolutePath(validating: #file.replacingOccurrences(of: "file://", with: ""))
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .appending(try RelativePath(validating: "projects/tuist/vendor"))
        if FileHandler.shared.exists(bundlePath) {
            return ["/usr/bin/xcrun", "swift", "run", "--package-path", bundlePath.pathString, "xcbeautify"]
        }
        bundlePath = try AbsolutePath(validating: Bundle(for: BinaryLocator.self).bundleURL.path)
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
            path.appending(components: "xcbeautify", "xcbeautify")
        }
        guard let existingPath = candidates.first(where: FileHandler.shared.exists) else {
            throw BinaryLocatorError.xcbeautifyNotFound
        }
        return [existingPath.pathString]
    }
}
