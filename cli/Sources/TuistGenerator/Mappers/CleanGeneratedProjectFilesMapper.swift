import Path
import TuistConstants
import TuistCore
import XcodeGraph

/// Removes obsolete generated project files after their replacements have been described.
public struct CleanGeneratedProjectFilesMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        let activeFiles = project.targets.values.flatMap { target in
            target.sources.map(\.path) + [target.infoPlist?.path, target.entitlements?.path].compactMap { $0 }
        }
        let generatedFiles = [
            (Constants.DerivedDirectory.sources, "Tuist*.swift"),
            (Constants.DerivedDirectory.infoPlists, "*-Info.plist"),
            (Constants.DerivedDirectory.entitlements, "*.entitlements"),
        ]
        let sideEffects = generatedFiles.map { directoryName, pattern in
            cleanup(project: project, directoryName: directoryName, pattern: pattern, activeFiles: activeFiles)
        }
        return (project, sideEffects)
    }

    private func cleanup(
        project: Project,
        directoryName: String,
        pattern: String,
        activeFiles: [AbsolutePath]
    ) -> SideEffectDescriptor {
        let directory = project.path.appending(components: Constants.DerivedDirectory.name, directoryName)
        return .generatedFilesCleanup(GeneratedFilesCleanupDescriptor(
            directories: [directory],
            activeFilesByDirectory: [directory: Set(activeFiles.filter { $0.parentDirectory == directory })],
            include: [pattern]
        ))
    }
}
