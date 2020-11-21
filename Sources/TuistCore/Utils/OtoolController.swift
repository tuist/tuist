import Foundation
import RxSwift
import TSCBasic
import TuistSupport

enum OtoolErrors: FatalError, Equatable {
    case invalidOutput

    var description: String {
        switch self {
        case .invalidOutput: return "The output is not in the format tuist expects"
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidOutput: return .abort
        }
    }
}

/// Otool controller protocol passed in initializers for dependency injection
public protocol OtoolControlling {
    /// Returns the paths to dlyb dependencies.
    /// - Parameter path: Path to the given dependency
    /// - Returns Array of dependencies returned by the command.
    func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> Single<[AbsolutePath]>
}

/// OtoolController
/// Used to find out against which dynamic libraries a certain binary is linked.
public struct OtoolController: OtoolControlling {
    private let system: Systeming

    public init(system: Systeming = System.shared) {
        self.system = system
    }

    public func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> Single<[AbsolutePath]> {
        let arguments = ["otool", "-L", path.pathString]

        return System.shared.observable(arguments)
            .mapToString()
            .collectAndMergeOutput()
            .map { try OtoolOutput(filePath: path, output: $0) }
            .map { $0.paths }
            .asSingle()
    }

    /// Given a framework path it returns the path to its binary.
    /// - Parameter frameworkPath: Framework path.
    func binaryPath(frameworkPath: AbsolutePath) -> AbsolutePath {
        let frameworkName = frameworkPath.basename.replacingOccurrences(of: ".framework", with: "")
        return frameworkPath.appending(component: frameworkName)
    }
}

/// Otool output example:
/// After running `otool -L path/to/AlamofireImage.framework/AlamofireImage` you will see something like this:
///
/// path/to/AlamofireImage.framework/AlamofireImage:
///    @rpath/AlamofireImage.framework/AlamofireImage (compatibility version 1.0.0, current version 1.0.0)
///    @rpath/Alamofire.framework/Alamofire (compatibility version 1.0.0, current version 1.0.0)
///    /usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)
///    /System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 1.0.0, current version 3987.9.0)
///    @rpath/libswiftCore.dylib (compatibility version 1.0.0, current version 1200.2.26)
///

private struct OtoolOutput {
    let paths: [AbsolutePath]

    init(filePath: AbsolutePath, output: String) throws {
        let outputByNewLines = Array(output.components(separatedBy: .newlines))
        // first line contains an ':'at the end
        guard outputByNewLines.first == "\(filePath.pathString):" else { throw OtoolErrors.invalidOutput }

        // we need to remove the /FrameworkName.framework/FrameworkName
        let folderPath = filePath.removingLastComponent().removingLastComponent()

        paths = outputByNewLines
            .dropFirst() // first line is the path to the framework
            .dropLast() // last is an empty line
            .filter { $0.contains("@rpath") } // the rest are system libraries
            .filter { !$0.contains("dylib") } // swift libs
            .map { $0.replacingOccurrences(of: "@rpath", with: folderPath.pathString) }
            .compactMap { $0.split(separator: " ").first } // drop compatibility
            .map { AbsolutePath($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
