import Foundation
import TSCBasic
import TuistSupport

/// Otool controller protocol passed in initializers for dependency injection
public protocol OtoolControlling {
    func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> [String]
}

/// OtoolController
/// Used to find out against which dynamic libraries a certain binary is linked.
public struct OtoolController: OtoolControlling {

    private let system: Systeming

    public init(system: Systeming = System.shared) {
        self.system = system
    }

    public func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> [String] {
        let arguments = ["otool", "-L", path.pathString]

        return try System.shared.capture(arguments)
            .components(separatedBy: .newlines)
            .dropFirst() // first line is the path to the framework
            .dropLast() // last is an empty line
            .compactMap { $0.dropFirst().split(separator: " ").first } // we remove the \t and  compatibility
            .map { String($0) }
    }

    /// Given a framework path it returns the path to its binary.
    /// - Parameter frameworkPath: Framework path.
    func binaryPath(frameworkPath: AbsolutePath) -> AbsolutePath {
        let frameworkName = frameworkPath.basename.replacingOccurrences(of: ".framework", with: "")
        return frameworkPath.appending(component: frameworkName)
    }

}


