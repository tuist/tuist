import Path
import TuistCore
import TuistLogging
import XcodeGraph

/// A project mapper that creates generated target script file lists.
public struct GenerateTargetScriptFileListProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        Logger.current.debug("Transforming project \(project.name): Generating target script file lists")

        let fileListPaths = project.targets.values
            .flatMap(\.scripts)
            .flatMap { $0.inputFileListPaths + $0.outputFileListPaths }
            .compactMap { fileListPath in
                if case let .generated(path) = fileListPath {
                    return path
                }
                return nil
            }
            .reduce(into: [AbsolutePath]()) { paths, path in
                if !paths.contains(path) {
                    paths.append(path)
                }
            }

        return (
            project,
            fileListPaths.map { SideEffectDescriptor.file(FileDescriptor(path: $0)) }
        )
    }
}
