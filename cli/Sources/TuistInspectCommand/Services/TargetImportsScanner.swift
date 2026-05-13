#if os(macOS)
    import FileSystem
    import Mockable
    import Path
    import XcodeGraph

    @Mockable
    protocol TargetImportsScanning {
        func imports(
            for target: XcodeGraph.Target,
            reachableModules: Set<String>?
        ) async throws -> Set<String>
    }

    extension TargetImportsScanning {
        /// Convenience that scans without `canImport` awareness.
        func imports(for target: XcodeGraph.Target) async throws -> Set<String> {
            try await imports(for: target, reachableModules: nil)
        }
    }

    struct TargetImportsScanner: TargetImportsScanning {
        private let importSourceCodeScanner: ImportSourceCodeScanner
        private let maxConcurrentFileScans: Int
        private let sourceCodeReader: (AbsolutePath) async throws -> String?

        init(
            importSourceCodeScanner: ImportSourceCodeScanner = ImportSourceCodeScanner(),
            fileSystem: FileSysteming = FileSystem(),
            maxConcurrentFileScans: Int = 100
        ) {
            self.init(
                importSourceCodeScanner: importSourceCodeScanner,
                maxConcurrentFileScans: maxConcurrentFileScans
            ) { path in
                guard try await fileSystem.exists(path) else { return nil }
                return try await fileSystem.readTextFile(at: path)
            }
        }

        init(
            importSourceCodeScanner: ImportSourceCodeScanner = ImportSourceCodeScanner(),
            maxConcurrentFileScans: Int = 100,
            sourceCodeReader: @escaping (AbsolutePath) async throws -> String?
        ) {
            self.importSourceCodeScanner = importSourceCodeScanner
            self.maxConcurrentFileScans = max(1, maxConcurrentFileScans)
            self.sourceCodeReader = sourceCodeReader
        }

        func imports(
            for target: XcodeGraph.Target,
            reachableModules: Set<String>?
        ) async throws -> Set<String> {
            var filesToScan = target.sources.map(\.path) + target.buildableFolders.flatMap(\.resolvedFiles).map(\.path)
                .filter { Target.validSourceExtensions.contains($0.extension ?? "") }
            if let headers = target.headers {
                filesToScan.append(contentsOf: headers.private)
                filesToScan.append(contentsOf: headers.public)
                filesToScan.append(contentsOf: headers.project)
            }
            var imports = Set(
                try await filesToScan.concurrentMap(maxConcurrentTasks: maxConcurrentFileScans) { file in
                    try await matchPattern(at: file, reachableModules: reachableModules)
                }
                .flatMap { $0 }
            )
            imports.remove(target.productName)
            return imports
        }

        private func matchPattern(
            at path: AbsolutePath,
            reachableModules: Set<String>?
        ) async throws -> Set<String> {
            let language: ProgrammingLanguage
            switch path.extension {
            case "swift":
                language = .swift
            case "h", "m", "cpp", "mm":
                language = .objc
            default:
                return []
            }

            guard let sourceCode = try await sourceCodeReader(path) else {
                return Set()
            }

            return try importSourceCodeScanner.extractImports(
                from: sourceCode,
                language: language,
                reachableModules: reachableModules
            )
        }
    }
#endif
