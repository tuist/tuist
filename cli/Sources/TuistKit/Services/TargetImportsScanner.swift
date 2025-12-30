import FileSystem
import Mockable
import Path
import XcodeGraph

@Mockable
protocol TargetImportsScanning {
    func imports(for target: XcodeGraph.Target) async throws -> Set<String>
}

final class TargetImportsScanner: TargetImportsScanning {
    private let importSourceCodeScanner: ImportSourceCodeScanner
    private let fileSystem: FileSystem

    init(
        importSourceCodeScanner: ImportSourceCodeScanner = ImportSourceCodeScanner(),
        fileSystem: FileSystem = FileSystem()
    ) {
        self.importSourceCodeScanner = importSourceCodeScanner
        self.fileSystem = fileSystem
    }

    func imports(for target: XcodeGraph.Target) async throws -> Set<String> {
        var filesToScan = target.sources.map(\.path) + target.buildableFolders.flatMap(\.resolvedFiles).map(\.path)
            .filter { Target.validSourceExtensions.contains($0.extension ?? "") }
        if let headers = target.headers {
            filesToScan.append(contentsOf: headers.private)
            filesToScan.append(contentsOf: headers.public)
            filesToScan.append(contentsOf: headers.project)
        }
        var imports = Set(
            try await filesToScan.concurrentMap(maxConcurrentTasks: 100) { file in
                try await self.matchPattern(at: file)
            }
            .flatMap { $0 }
        )
        imports.remove(target.productName)
        return imports
    }

    private func matchPattern(at path: AbsolutePath) async throws -> Set<String> {
        let language: ProgrammingLanguage
        switch path.extension {
        case "swift":
            language = .swift
        case "h", "m", "cpp", "mm":
            language = .objc
        default:
            return []
        }

        // Targets might contain references to absent files, either by mistake
        // or because those files are generated later on, as is the case with generated
        // projects with synthesized files. Therefore, we can't assume their existence.
        if try await fileSystem.exists(path) {
            let sourceCode = try await fileSystem.readTextFile(at: path)
            return try importSourceCodeScanner.extractImports(
                from: sourceCode,
                language: language
            )
        } else {
            return Set()
        }
    }
}
