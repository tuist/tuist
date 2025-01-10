import FileSystem
import Mockable
import Path
import XcodeGraph
private import struct NIOFileSystem.FileSystemError

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
        var filesToScan = target.sources.map(\.path)
        if let headers = target.headers {
            filesToScan.append(contentsOf: headers.private)
            filesToScan.append(contentsOf: headers.public)
            filesToScan.append(contentsOf: headers.project)
        }
        var imports = Set(
            try await filesToScan.concurrentMap { file in
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

        let sourceCode = try await readFile(at: path)
        return try importSourceCodeScanner.extractImports(
            from: sourceCode,
            language: language
        )
    }
    
    private func readFile(at path: AbsolutePath) async throws -> String {
        do {
            return try await fileSystem.readTextFile(at: path)
        } catch let error as NIOFileSystem.FileSystemError where error.code == .unavailable {
            guard let error = error.cause as? NIOFileSystem.FileSystemError.SystemCallError else {
                throw error
            }
            guard error.errno == .tooManyOpenFiles else {
                throw error
            }
            try await Task.sleep(for: .seconds(1))
            return try await readFile(at: path)
        } catch {
            throw error
        }
    }
}
