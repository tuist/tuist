import Mockable
import Path
import TuistCore
import TuistLoader
import XcodeGraph

@Mockable
protocol LocalPackageCoverageTargetsValidating {
    /// Validates the scheme code coverage references that point at local Swift packages,
    /// checking the referenced name against the products of the referenced package.
    /// Invalid references are removed from the returned graph, with a warning for each,
    /// so that coverage falls back to all targets instead of producing an empty report.
    /// - Parameters:
    ///   - graph: The graph whose schemes should be validated.
    ///   - disableSandbox: Whether the sandbox should be disabled when dumping the package.
    func validate(graph: Graph, disableSandbox: Bool) async throws -> (Graph, [LintingIssue])
}

struct LocalPackageCoverageTargetsValidator: LocalPackageCoverageTargetsValidating {
    private let packageInfoLoader: PackageInfoLoading

    init(packageInfoLoader: PackageInfoLoading = PackageInfoLoader()) {
        self.packageInfoLoader = packageInfoLoader
    }

    func validate(graph: Graph, disableSandbox: Bool) async throws -> (Graph, [LintingIssue]) {
        let localPackagePaths = Set(
            graph.projects.values
                .flatMap(\.packages)
                .compactMap { package -> AbsolutePath? in
                    guard case let .local(path) = package else { return nil }
                    return path
                }
        )
        guard !localPackagePaths.isEmpty else { return (graph, []) }

        var graph = graph
        var issues: [LintingIssue] = []
        var productsCache: [AbsolutePath: Set<String>] = [:]

        func products(at path: AbsolutePath) async throws -> Set<String> {
            if let cached = productsCache[path] { return cached }
            let packageInfo = try await packageInfoLoader.loadPackageInfo(at: path, disableSandbox: disableSandbox)
            let products = Set(packageInfo.products.map(\.name))
            productsCache[path] = products
            return products
        }

        func validate(scheme: Scheme) async throws -> Scheme {
            guard let testAction = scheme.testAction, !testAction.codeCoverageTargets.isEmpty else { return scheme }
            var scheme = scheme
            var validReferences: [TargetReference] = []
            for reference in testAction.codeCoverageTargets {
                if graph.projects[reference.projectPath]?.targets[reference.name] != nil
                    || !localPackagePaths.contains(reference.projectPath)
                {
                    validReferences.append(reference)
                    continue
                }
                if try await products(at: reference.projectPath).contains(reference.name) {
                    validReferences.append(reference)
                } else {
                    issues.append(LintingIssue(
                        reason: "The target '\(reference.name)' specified in \(scheme.name) code coverage targets list isn't a product of the package at '\(reference.projectPath.relative(to: graph.path).pathString)'. The reference will be ignored.",
                        severity: .warning
                    ))
                }
            }
            scheme.testAction?.codeCoverageTargets = validReferences
            return scheme
        }

        for (path, project) in graph.projects {
            var project = project
            var schemes: [Scheme] = []
            for scheme in project.schemes {
                schemes.append(try await validate(scheme: scheme))
            }
            project.schemes = schemes
            graph.projects[path] = project
        }

        var workspaceSchemes: [Scheme] = []
        for scheme in graph.workspace.schemes {
            workspaceSchemes.append(try await validate(scheme: scheme))
        }
        graph.workspace.schemes = workspaceSchemes

        return (graph, issues)
    }
}
