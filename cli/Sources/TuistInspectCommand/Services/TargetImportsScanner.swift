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
        /// Scanned imports of every file read so far. Checks for implicit and redundant dependencies, and
        /// targets sharing sources, resolve the same files with different reachable modules.
        private let scannedImportsCache = ScannedImportsCache()

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
                    ImportSourceCodeScanner.imports(in: try await scannedImports(at: file), reachableModules: reachableModules)
                }
                .flatMap { $0 }
            )
            imports.remove(target.productName)
            return imports
        }

        private func scannedImports(at path: AbsolutePath) async throws -> [ScannedImport] {
            if let scannedImports = await scannedImportsCache.scannedImports(at: path) {
                return scannedImports
            }

            let language: ProgrammingLanguage
            switch path.extension {
            case "swift":
                language = .swift
            case "h", "m", "cpp", "mm":
                language = .objc
            default:
                return []
            }

            let scannedImports = if let sourceCode = try await sourceCodeReader(path) {
                importSourceCodeScanner.scanImports(from: sourceCode, language: language)
            } else {
                [ScannedImport]()
            }
            await scannedImportsCache.store(scannedImports, at: path)
            return scannedImports
        }
    }

    private actor ScannedImportsCache {
        private var scannedImportsByPath: [AbsolutePath: [ScannedImport]] = [:]

        func scannedImports(at path: AbsolutePath) -> [ScannedImport]? {
            scannedImportsByPath[path]
        }

        func store(_ scannedImports: [ScannedImport], at path: AbsolutePath) {
            scannedImportsByPath[path] = scannedImports
        }
    }
#endif
