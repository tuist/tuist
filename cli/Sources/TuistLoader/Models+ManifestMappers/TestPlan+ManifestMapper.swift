import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistAlert
import TuistConstants
import TuistSupport
import XcodeGraph

extension XcodeGraph.TestPlan {
    /// Resolves a list of `ProjectDescription.TestPlan` entries into the graph's `TestPlan` values,
    /// expanding globs for path entries and computing derived paths for generated ones. The first
    /// resolved plan is marked as the default.
    static func resolve(
        entries: [ProjectDescription.TestPlan],
        generatorPaths: GeneratorPaths,
        schemeName: String?,
        fileSystem: FileSystem
    ) async throws -> [XcodeGraph.TestPlan] {
        let derivedDirectory = generatorPaths.manifestDirectory
            .appending(
                components: Constants.DerivedDirectory.name,
                Constants.DerivedDirectory.testPlans
            )

        var resolved: [XcodeGraph.TestPlan] = []
        for entry in entries {
            switch entry {
            case let .path(path):
                try await appendPathEntry(
                    path: path,
                    generatorPaths: generatorPaths,
                    schemeName: schemeName,
                    fileSystem: fileSystem,
                    into: &resolved
                )
            case let .generated(name, testTargets, path):
                let resolvedPath: AbsolutePath = if let explicitPath = path {
                    try generatorPaths.resolve(path: explicitPath)
                } else {
                    derivedDirectory.appending(component: "\(name).xctestplan")
                }
                let targets = try testTargets.map {
                    try TestableTarget.from(manifest: $0, generatorPaths: generatorPaths)
                }
                resolved.append(
                    XcodeGraph.TestPlan(
                        path: resolvedPath,
                        testTargets: targets,
                        isDefault: resolved.isEmpty,
                        kind: .generated
                    )
                )
            }
        }

        return resolved
    }

    /// Reads an existing `.xctestplan` file and maps it into the graph model. `TestPlan.resolve`
    /// is the normal entry point; this method is exposed for call sites that already have a
    /// resolved path in hand.
    static func from(
        path: AbsolutePath,
        isDefault: Bool,
        generatorPaths: GeneratorPaths
    ) async throws -> XcodeGraph.TestPlan {
        let fileSystem = FileSystem()
        let xcTestPlan: XCTestPlan = try await fileSystem.readJSONFile(at: path, decoder: JSONDecoder())

        return try XcodeGraph.TestPlan(
            path: path,
            testTargets: xcTestPlan.testTargets.map { testTarget in
                let relativeProjectPath = projectRelativePath(from: testTarget.target.containerPath)
                let projectPath: AbsolutePath = if relativeProjectPath.isEmpty {
                    generatorPaths.manifestDirectory
                } else {
                    try generatorPaths.resolve(path: .relativeToManifest(relativeProjectPath))
                        .removingLastComponent()
                }
                return try TestableTarget(
                    target: TargetReference(
                        projectPath: projectPath,
                        name: testTarget.target.name
                    ),
                    skipped: !(testTarget.enabled ?? true)
                )
            },
            isDefault: isDefault
        )
    }

    private static func appendPathEntry(
        path: ProjectDescription.Path,
        generatorPaths: GeneratorPaths,
        schemeName: String?,
        fileSystem: FileSystem,
        into resolved: inout [XcodeGraph.TestPlan]
    ) async throws {
        let resolvedPath = try generatorPaths.resolve(path: path)
        let pathString = resolvedPath.pathString

        if pathString.contains("*") {
            let globPathString = String(pathString.dropFirst())
            do {
                let globPaths = try await fileSystem
                    .throwingGlob(directory: .root, include: [globPathString])
                    .collect()
                    .filter { $0.extension == "xctestplan" }
                    .sorted()

                for globPath in globPaths {
                    let testPlan = try await XcodeGraph.TestPlan.from(
                        path: globPath,
                        isDefault: resolved.isEmpty,
                        generatorPaths: generatorPaths
                    )
                    resolved.append(testPlan)
                }
            } catch GlobError.nonExistentDirectory {
                // Skip non-existent glob patterns.
            }
            return
        }

        guard try await fileSystem.exists(resolvedPath) else {
            let schemeContext = schemeName.map { " referenced by the scheme '\($0)'" } ?? ""
            AlertController.current.warning(
                .alert(
                    "Test plan \(resolvedPath.basename) does not exist at \(resolvedPath.pathString)\(schemeContext)"
                )
            )
            return
        }

        guard resolvedPath.extension == "xctestplan" else { return }

        let testPlan = try await XcodeGraph.TestPlan.from(
            path: resolvedPath,
            isDefault: resolved.isEmpty,
            generatorPaths: generatorPaths
        )
        resolved.append(testPlan)
    }

    /// Strips the `container:` prefix from an `.xctestplan` container path, returning the
    /// project-relative portion that follows it. Returns the input unchanged when no prefix is
    /// present.
    private static func projectRelativePath(from containerPath: String) -> String {
        let prefix = "container:"
        guard containerPath.hasPrefix(prefix) else { return containerPath }
        return String(containerPath.dropFirst(prefix.count))
    }
}
