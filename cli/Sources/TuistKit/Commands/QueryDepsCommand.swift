import ArgumentParser
import Foundation
import Path
import TuistSupport

public struct QueryDepsCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "deps",
            abstract: "Query dependencies of targets in the project graph."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory,
        envKey: .queryDepsPath
    )
    var path: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Show dependencies of these targets (what they depend on).",
        envKey: .queryDepsSource
    )
    var source: [String] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Show targets that depend on these targets (reverse dependencies).",
        envKey: .queryDepsSink
    )
    var sink: [String] = []

    @Flag(
        name: .long,
        help: "Show only direct dependencies instead of transitive.",
        envKey: .queryDepsDirect
    )
    var direct: Bool = false

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Filter by dependency type: target, package, framework, xcframework, sdk, bundle, library, macro.",
        envKey: .queryDepsType
    )
    var type: [String] = []

    @Option(
        name: [.customShort("f"), .long],
        help: "Output format: list, tree, json.",
        envKey: .queryDepsFormat
    )
    var format: QueryDepsFormat = .list

    public func run() async throws {
        try await QueryDepsService().run(
            path: path.map { try AbsolutePath(validating: $0) } ?? FileHandler.shared.currentPath,
            sourceTargets: source,
            sinkTargets: sink,
            directOnly: direct,
            typeFilter: Set(type),
            format: format
        )
    }
}

public enum QueryDepsFormat: String, ExpressibleByArgument, CaseIterable {
    case list
    case tree
    case json
}
