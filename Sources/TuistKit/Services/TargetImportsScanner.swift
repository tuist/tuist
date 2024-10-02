import FileSystem
import Mockable
import Path
import XcodeGraph

struct ModuleImport: Equatable {
    let module: String
    let line: Int
    let file: AbsolutePath
}

@Mockable
protocol TargetImportsScanning {
    func imports(for target: XcodeGraph.Target) async throws -> [ModuleImport]
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

    func imports(for target: XcodeGraph.Target) async throws -> [ModuleImport] {
        var filesToScan = target.sources.map(\.path)
        if let headers = target.headers {
            filesToScan.append(contentsOf: headers.private)
            filesToScan.append(contentsOf: headers.public)
            filesToScan.append(contentsOf: headers.project)
        }
        return try await filesToScan.concurrentMap { file in
            try await self.matchPattern(at: file)
        }
        .flatMap { $0 }
        .filter { $0.module != target.productName }
    }

    private func matchPattern(at path: AbsolutePath) async throws -> [ModuleImport] {
        let language: ProgrammingLanguage
        switch path.extension {
        case "swift":
            language = .swift
        case "h", "m", "cpp", "mm":
            language = .objc
        default:
            return []
        }

        let sourceCode = try await fileSystem.readTextFile(at: path)
        return try importSourceCodeScanner.extractImports(
            from: sourceCode,
            language: language
        )
        .map {
            ModuleImport(
                module: $0.module,
                line: $0.line,
                file: path
            )
        }
    }
}
