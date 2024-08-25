import FileSystem
import Path
import XcodeGraph

struct FileImport: Equatable {
    let module: String
    let line: Int
    let file: AbsolutePath
}

protocol TargetImportsScanning {
    func imports(for target: XcodeGraph.Target) async throws -> [FileImport]
}

final class TargetImportsScanner: TargetImportsScanning {
    private let importSourceCodeScanner: ImportSourceCodeScanner
    private let fileSystem = FileSystem()

    init(importSourceCodeScanner: ImportSourceCodeScanner = ImportSourceCodeScanner()) {
        self.importSourceCodeScanner = importSourceCodeScanner
    }

    func imports(for target: XcodeGraph.Target) async throws -> [FileImport] {
        var filesToScan = target.sources.map(\.path)
        if let headers = target.headers {
            filesToScan.append(contentsOf: headers.private)
            filesToScan.append(contentsOf: headers.public)
            filesToScan.append(contentsOf: headers.project)
        }
        var imports = try await filesToScan.concurrentMap { file in
            try await self.matchPattern(at: file)
        }
        .flatMap { $0 }
        .filter { $0.module != target.productName }
        return imports
    }

    private func matchPattern(at path: AbsolutePath) async throws -> [FileImport] {
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
            FileImport(
                module: $0.module,
                line: $0.line,
                file: path
            )
        }
    }
}
