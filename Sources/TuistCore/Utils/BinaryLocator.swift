import Foundation
import TSCBasic
import TuistSupport

enum BinaryLocatorError: FatalError, Equatable {
    case xcbeautifyNotFound
    case cocoapodsInteractorNotFound

    var description: String {
        switch self {
        case .xcbeautifyNotFound:
            return "Couldn't find the xcbeautify binary."
        case .cocoapodsInteractorNotFound:
            return "Couldn't find the cocoapods-interactor executable."
        }
    }

    var type: ErrorType {
        switch self {
        case .xcbeautifyNotFound,
             .cocoapodsInteractorNotFound:
            return .bug
        }
    }
}

/// Protocol that defines the interface to locate the tuist binary in the environment.
public protocol BinaryLocating {
    /// Returns the path to the xcbeautify binary.
    func xcbeautifyPath() throws -> AbsolutePath

    /// Returns the path to the cocoapods-interactor executable
    func cocoapodsInteractorPath() throws -> AbsolutePath
}

public final class BinaryLocator: BinaryLocating {
    public init() {}

    private func binariesPaths() throws -> [AbsolutePath] {
        #if DEBUG
            // Used only for debug purposes
            let bundlePath = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(RelativePath("projects/tuist/vendor"))
        #else
            let bundlePath = AbsolutePath(Bundle(for: BinaryLocator.self).bundleURL.path)
        #endif
        return [
            bundlePath,
            bundlePath.parentDirectory,
            bundlePath.appending(RelativePath("vendor")),
        ]
    }

    public func cocoapodsInteractorPath() throws -> AbsolutePath {
        #if DEBUG
            // Used only for debug purposes
            let path = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(RelativePath("projects/cocoapods-interactor/bin/cocoapods-interactor"))
        #else
            let path = AbsolutePath(
                Bundle(for: BinaryLocator.self).bundleURL.path
            )
            .appending(RelativePath("cocoapods-interactor/bin/cocoapods-interactor"))
        #endif
        guard FileHandler.shared.exists(path) else {
            throw BinaryLocatorError.cocoapodsInteractorNotFound
        }
        return path
    }

    public func xcbeautifyPath() throws -> AbsolutePath {
        let candidates = try binariesPaths().map { path in
            path.appending(components: Constants.Vendor.xcbeautify, Constants.Vendor.xcbeautify)
        }

        guard let existingPath = candidates.first(where: FileHandler.shared.exists) else {
            throw BinaryLocatorError.xcbeautifyNotFound
        }
        return existingPath
    }
}
