import FileSystem
import Foundation
import Path
import XcodeGraph

extension TestPlan {
    static func from(
        path: AbsolutePath,
        isDefault: Bool,
        generatorPaths: GeneratorPaths
    ) async throws -> TestPlan {
        let fileSystem = FileSystem()
        let xcTestPlan: XCTestPlan = try await fileSystem.readJSONFile(at: path, decoder: JSONDecoder())

        return try TestPlan(
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
}

/// Strips the `container:` prefix from an `.xctestplan` container path, returning the
/// project-relative portion that follows it. Returns the input unchanged when no prefix is
/// present.
private func projectRelativePath(from containerPath: String) -> String {
    let prefix = "container:"
    guard containerPath.hasPrefix(prefix) else { return containerPath }
    return String(containerPath.dropFirst(prefix.count))
}
