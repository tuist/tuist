import Mockable
import Path
import XcodeGraph
import Foundation

@Mockable
protocol TargetImportsScanning {
    func imports(for target: XcodeGraph.Target) async throws -> Set<String>
}

final class TargetImportsScanner: TargetImportsScanning {
    private let importSourceCodeScanner: ImportSourceCodeScanner

    init(
        importSourceCodeScanner: ImportSourceCodeScanner = ImportSourceCodeScanner()
    ) {
        self.importSourceCodeScanner = importSourceCodeScanner
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
                try self.matchPattern(at: file)
            }
            .flatMap { $0 }
        )
        imports.remove(target.productName)
        return imports
    }

    private func matchPattern(at path: AbsolutePath) throws -> Set<String> {
        let language: ProgrammingLanguage
        switch path.extension {
        case "swift":
            language = .swift
        case "h", "m", "cpp", "mm":
            language = .objc
        default:
            return []
        }

        let sourceCode = try readFile(at: path)
        return try importSourceCodeScanner.extractImports(
            from: sourceCode,
            language: language
        )
    }
    
    private func readFile(at path: AbsolutePath) throws -> String {
        let encoding = String.Encoding.utf8
        return try NSString(contentsOfFile: path.pathString, encoding: encoding.rawValue) as String
    }
}
