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
        private let scannedImportsCache: ScannedImportsCache

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
            scannedImportsCache = ScannedImportsCache(maxConcurrentScans: self.maxConcurrentFileScans)
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
            let language: ProgrammingLanguage
            switch path.extension {
            case "swift":
                language = .swift
            case "h", "m", "cpp", "mm":
                language = .objc
            default:
                return []
            }

            return try await scannedImportsCache.scannedImports(at: path) { [importSourceCodeScanner, sourceCodeReader] in
                guard let sourceCode = try await sourceCodeReader(path) else { return [] }
                return importSourceCodeScanner.scanImports(from: sourceCode, language: language)
            }
        }
    }

    /// Scans every file once, however many targets ask for it at the same time, and runs at most
    /// `maxConcurrentScans` scans at once across all targets so concurrent targets can't exhaust file descriptors.
    private actor ScannedImportsCache {
        private let maxConcurrentScans: Int
        private var activeScans = 0
        private var waitingScans: [CheckedContinuation<Void, Never>] = []
        private var scansByPath: [AbsolutePath: Task<[ScannedImport], Error>] = [:]

        init(maxConcurrentScans: Int) {
            self.maxConcurrentScans = maxConcurrentScans
        }

        func scannedImports(
            at path: AbsolutePath,
            scan: @escaping @Sendable () async throws -> [ScannedImport]
        ) async throws -> [ScannedImport] {
            if let task = scansByPath[path] {
                return try await task.value
            }
            let task = Task { try await withScanSlot(scan) }
            scansByPath[path] = task
            return try await task.value
        }

        private func withScanSlot(_ scan: () async throws -> [ScannedImport]) async throws -> [ScannedImport] {
            if activeScans < maxConcurrentScans {
                activeScans += 1
            } else {
                await withCheckedContinuation { waitingScans.append($0) }
            }
            // A finished scan hands its slot to the next waiting scan, if any.
            defer {
                if waitingScans.isEmpty {
                    activeScans -= 1
                } else {
                    waitingScans.removeFirst().resume()
                }
            }
            return try await scan()
        }
    }
#endif
