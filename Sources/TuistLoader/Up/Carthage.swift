import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Model that represents the content of the file that Carthage
/// generates for each resolved dependency.
struct CarthageVersionFile: Codable {
    /// The git revision of the resolved dependency.
    let commitish: String
}

/// Protocol that defines an interface to interact with a local Carthage setup.
protocol Carthaging {
    /// Bootstraps the dependencies in the given directory.
    ///
    /// - Parameters:
    ///   - path: Directory where the Carthage dependencies are defined.
    ///   - platforms: Platforms the dependencies will be bootstraped for.
    ///   - dependencies: Dependencies to bootstrap
    /// - Throws: An error if the dependencies bootstrap fails.
    func bootstrap(path: AbsolutePath, platforms: [Platform], dependencies: [String]) throws

    /// Returns the list of outdated dependencies in the given directory.
    ///
    /// - Parameter path: Project directory.
    /// - Returns: List of outdated dependencies.
    func outdated(path: AbsolutePath) throws -> [String]?
}

final class Carthage: Carthaging {
    /// Regex used to match and extract information from the lines in the Cartfile.resolved file.
    // swiftlint:disable:next force_try
    static let resolvedLineRegex = try! NSRegularExpression(pattern: "(github|git|binary) \"([^\"]+)\" \"([^\"]+)\"", options: [])

    /// Bootstraps the dependencies in the given directory.
    ///
    /// - Parameters:
    ///   - path: Directory where the Carthage dependencies are defined.
    ///   - platforms: Platforms the dependencies will be bootstraped for.
    ///   - dependencies: Dependencies to bootstrap
    /// - Throws: An error if the dependencies bootstrap fails.
    func bootstrap(path: AbsolutePath, platforms: [Platform], dependencies: [String]) throws {
        let carthagePath = try System.shared.which("carthage")

        var command: [String] = [carthagePath]
        command.append("bootstrap")
        command.append("--project-directory")
        command.append(path.pathString)

        if !platforms.isEmpty {
            command.append("--platform")
            command.append(platforms.map { $0.caseValue }.joined(separator: ","))
        }

        command.append(contentsOf: dependencies)

        try System.shared.run(command)
    }

    /// Returns the list of outdated dependencies in the given directory.
    /// Reference: https://github.com/Carthage/workflows/blob/master/carthage-verify
    ///
    /// - Parameter path: Project directory.
    /// - Returns: List of outdated dependencies.
    func outdated(path: AbsolutePath) throws -> [String]? {
        let cartfileResolvedPath = path.appending(component: "Cartfile.resolved")

        if !FileHandler.shared.exists(cartfileResolvedPath) {
            return nil
        }

        var outdated: [String] = []
        let carfileResolved = try FileHandler.shared.readTextFile(cartfileResolvedPath)
        let carfileResolvedNSString = carfileResolved as NSString
        let jsonDecoder = JSONDecoder()

        try Carthage.resolvedLineRegex.matches(in: carfileResolved,
                                               options: [],
                                               range: NSRange(location: 0,
                                                              length: carfileResolved.count)).forEach { match in
            let dependencyNameRange = match.range(at: 2)
            var dependencyName = String(carfileResolvedNSString.substring(with: dependencyNameRange).split(separator: "/").last!)

            let dependencyTypeRange = match.range(at: 1)
            let dependencyType = DependencyType(rawValue: carfileResolvedNSString.substring(with: dependencyTypeRange))
            if dependencyType == .binary {
                dependencyName = (dependencyName as NSString).deletingPathExtension
            }

            let dependencyRevisionRange = match.range(at: 3)
            let dependencyRevision = carfileResolvedNSString.substring(with: dependencyRevisionRange)

            let dependencyVersionFilePath = path.appending(RelativePath("Carthage/Build/.\(dependencyName).version"))

            // We consider missing dependencies outdated
            if !FileHandler.shared.exists(dependencyVersionFilePath) {
                outdated.append(dependencyName)
                return
            }

            let dependencyVersionData = try Data(contentsOf: dependencyVersionFilePath.url)
            let dependencyVersionFile = try jsonDecoder.decode(CarthageVersionFile.self, from: dependencyVersionData)

            if dependencyVersionFile.commitish != dependencyRevision {
                outdated.append(dependencyName)
            }
        }

        return outdated
    }
}

extension Carthage {
    private enum DependencyType: String {
        case github, git, binary
    }
}
