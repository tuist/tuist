import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol BuildGraphInspecting {
    /// Returns the build arguments to be used with the given target.
    /// - Parameter target: Target whose build arguments will be returned.
    /// - Parameter configuration: The configuration to be built. When nil, it defaults to the configuration specified in the scheme.
    func buildArguments(target: Target, configuration: String?) -> [XcodeBuildArgument]

    /// Given a directory, it returns the first .xcworkspace found.
    /// - Parameter path: Found .xcworkspace.
    func workspacePath(directory: AbsolutePath) throws -> AbsolutePath?

    ///  From the list of buildable targets of the given scheme, it returns the first one.
    /// - Parameters:
    ///   - scheme: Scheme in which to look up the target.
    ///   - graph: Dependency graph.
    func buildableTarget(scheme: Scheme, graph: Graph) -> Target?

    /// Given a graph, it returns a list of buildable schemes.
    /// - Parameter graph: Dependency graph.
    func buildableSchemes(graph: Graph) -> [Scheme]
}

public class BuildGraphInspector: BuildGraphInspecting {
    public init() {}

    public func buildArguments(target: Target, configuration: String?) -> [XcodeBuildArgument] {
        var arguments: [XcodeBuildArgument]
        if target.platform == .macOS {
            arguments = [.sdk(target.platform.xcodeDeviceSDK)]
        } else {
            arguments = [.sdk(target.platform.xcodeSimulatorSDK!)]
        }

        // Configuration
        if let configuration = configuration {
            if target.settings?.configurations.first(where: { $0.key.name == configuration }) != nil {
                arguments.append(.configuration(configuration))
            } else {
                logger.warning("The scheme's targets don't have the given configuration \(configuration). Defaulting to the scheme's default.")
            }
        }

        return arguments
    }

    public func buildableTarget(scheme: Scheme, graph: Graph) -> Target? {
        if scheme.buildAction?.targets.count == 0 {
            return nil
        }
        let buildTarget = scheme.buildAction!.targets.first!
        return graph.target(path: buildTarget.projectPath, name: buildTarget.name)!.target
    }

    public func buildableSchemes(graph: Graph) -> [Scheme] {
        let projects = Set(graph.entryNodes.compactMap { ($0 as? TargetNode)?.project })
        return projects
            .flatMap { $0.schemes }
            .filter { $0.buildAction?.targets.count != 0 }
            .sorted(by: { $0.name < $1.name })
    }

    public func workspacePath(directory: AbsolutePath) throws -> AbsolutePath? {
        try directory.glob("**/*.xcworkspace")
            .filter {
                try FileHandler.shared.contentsOfDirectory($0)
                    .map(\.basename)
                    .contains(Constants.tuistGeneratedFileName)
            }
            .first
    }
}
