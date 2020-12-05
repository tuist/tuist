import Foundation
import RxSwift
import TSCBasic
import TuistSupport

enum OtoolError: FatalError, Equatable {
    case invalidOutput(String)

    var description: String {
        switch self {
        case let .invalidOutput(path):
            return """
                We couldn't get the dependencies of binary \(path) using otool because
                the output has an unexpected format.
                """
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidOutput: return .bug
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
    public init() {}

    public func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> Single<[AbsolutePath]> {
        let arguments = ["otool", "-L", path.pathString]

        return System.shared.observable(arguments)
            .mapToString()
            .collectAndMergeOutput()
            .map { try parseOtoolOutput(filePath: path, output: $0) }
            .asSingle()
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

private extension OtoolController {
    func parseOtoolOutput(filePath: AbsolutePath, output: String) throws -> [AbsolutePath] {
        logger.debug(.init(stringLiteral: output))

        let outputByNewLines = Array(output.components(separatedBy: .newlines))
        // first line contains an ':'at the end
        guard outputByNewLines.first == "\(filePath.pathString):" else {
            throw OtoolError.invalidOutput(filePath.pathString)
        }

        // we need to remove the /FrameworkName.framework/FrameworkName
        let folderPath = filePath.removingLastComponent().removingLastComponent()

        return outputByNewLines
            .dropFirst() // first line is the path to the framework
            .dropLast() // last is an empty line
            .filter { $0.contains("@rpath") } // the rest are system libraries
            .filter { !$0.contains("dylib") } // swift libs
            .map { $0.replacingOccurrences(of: "@rpath", with: folderPath.pathString) }
            .compactMap { $0.split(separator: " ").first } // drop compatibility
            .map { AbsolutePath($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
