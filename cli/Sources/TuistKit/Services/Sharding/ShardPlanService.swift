#if os(macOS)
    import FileSystem
    import Foundation
    import Mockable
    import Path
    import TuistAppleArchiver
    import TuistAutomation
    import TuistCI
    import TuistCore
    import TuistEnvironment
    import TuistLogging
    import TuistServer
    import TuistSupport

    @Mockable
    public protocol ShardPlanServicing {
        func plan(
            xctestproductsPath: AbsolutePath,
            destination: String?,
            reference: String?,
            shardGranularity: ShardGranularity,
            shardMin: Int?,
            shardMax: Int?,
            shardTotal: Int?,
            shardMaxDuration: Int?,
            fullHandle: String,
            serverURL: URL,
            buildRunId: String?,
            skipUpload: Bool,
            archivePath: AbsolutePath?
        ) async throws -> Components.Schemas.ShardPlan
    }

    public enum ShardPlanServiceError: LocalizedError, Equatable {
        case noTestModulesFound
        case cannotDeriveSessionId
        case xcTestRunNotFound(AbsolutePath)

        public var errorDescription: String? {
            switch self {
            case .noTestModulesFound:
                return "No test modules found in the .xctestproducts bundle."
            case .cannotDeriveSessionId:
                return
                    "Cannot derive a shard plan reference. Pass --shard-reference explicitly or run in a supported CI environment (GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic)."
            case let .xcTestRunNotFound(path):
                return "No .xctestrun file found in \(path.pathString)"
            }
        }
    }

    public struct ShardPlanService: ShardPlanServicing {
        private let xcTestEnumerator: XCTestEnumerating
        private let createShardPlanService: CreateShardPlanServicing
        private let startShardUploadService: StartShardUploadServicing
        private let multipartUploadArtifactService: MultipartUploadArtifactServicing
        private let multipartUploadGenerateURLShardsService: MultipartUploadGenerateURLShardsServicing
        private let multipartUploadCompleteShardsService: MultipartUploadCompleteShardsServicing
        private let ciController: CIControlling
        private let fileSystem: FileSysteming
        private let fileArchiver: FileArchivingFactorying
        private let shardMatrixOutputService: ShardMatrixOutputServicing
        private let appleArchiver: AppleArchiving

        public init(
            xcTestEnumerator: XCTestEnumerating = XCTestEnumerator(),
            createShardPlanService: CreateShardPlanServicing = CreateShardPlanService(),
            startShardUploadService: StartShardUploadServicing = StartShardUploadService(),
            multipartUploadArtifactService: MultipartUploadArtifactServicing = MultipartUploadArtifactService(),
            multipartUploadGenerateURLShardsService: MultipartUploadGenerateURLShardsServicing =
                MultipartUploadGenerateURLShardsService(),
            multipartUploadCompleteShardsService: MultipartUploadCompleteShardsServicing =
                MultipartUploadCompleteShardsService(),
            ciController: CIControlling = CIController(),
            fileSystem: FileSysteming = FileSystem(),
            fileArchiver: FileArchivingFactorying = FileArchivingFactory(),
            shardMatrixOutputService: ShardMatrixOutputServicing = ShardMatrixOutputService(),
            appleArchiver: AppleArchiving = AppleArchiver()
        ) {
            self.xcTestEnumerator = xcTestEnumerator
            self.createShardPlanService = createShardPlanService
            self.startShardUploadService = startShardUploadService
            self.multipartUploadArtifactService = multipartUploadArtifactService
            self.multipartUploadGenerateURLShardsService = multipartUploadGenerateURLShardsService
            self.multipartUploadCompleteShardsService = multipartUploadCompleteShardsService
            self.ciController = ciController
            self.fileSystem = fileSystem
            self.fileArchiver = fileArchiver
            self.shardMatrixOutputService = shardMatrixOutputService
            self.appleArchiver = appleArchiver
        }

        public func plan(
            xctestproductsPath: AbsolutePath,
            destination: String? = nil,
            reference: String?,
            shardGranularity: ShardGranularity,
            shardMin: Int?,
            shardMax: Int?,
            shardTotal: Int?,
            shardMaxDuration: Int?,
            fullHandle: String,
            serverURL: URL,
            buildRunId: String?,
            skipUpload: Bool = false,
            archivePath: AbsolutePath? = nil
        ) async throws -> Components.Schemas.ShardPlan {
            guard let reference = reference ?? ciController.ciInfo()?.shardReference else {
                throw ShardPlanServiceError.cannotDeriveSessionId
            }

            guard let xcTestRunPath = try await fileSystem
                .glob(directory: xctestproductsPath, include: ["**/*.xctestrun"])
                .collect()
                .first
            else {
                throw ShardPlanServiceError.xcTestRunNotFound(xctestproductsPath)
            }
            let xcTestRun: XCTestRun = try await fileSystem.readPlistFile(at: xcTestRunPath)
            let modules = xcTestRun.testModules

            guard !modules.isEmpty else {
                throw ShardPlanServiceError.noTestModulesFound
            }

            var testSuites: [String]?
            if shardGranularity == .suite {
                testSuites = try await enumerateTestSuites(
                    testProductsPath: xctestproductsPath,
                    destination: destination,
                    expectedModules: modules
                )
            }

            Logger.current.notice("Creating shard plan with \(modules.count) test module(s)", metadata: .section)

            let shardPlan = try await createShardPlanService.createShardPlan(
                fullHandle: fullHandle,
                serverURL: serverURL,
                reference: reference,
                modules: modules,
                testSuites: testSuites,
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration,
                shardGranularity: shardGranularity,
                buildRunId: buildRunId
            )

            Logger.current.notice("Shard plan created: \(shardPlan.shard_count) shards", metadata: .section)

            if let archivePath {
                try await archiveXCTestProducts(xctestproductsPath, to: archivePath)
                Logger.current.notice("Shard archive written to \(archivePath.pathString)", metadata: .section)
            } else if skipUpload {
                Logger.current
                    .notice("Skipping test products upload. Ensure shard runners can access the test products locally.")
            } else {
                let uploadId = try await startShardUploadService.startUpload(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    shardPlanId: shardPlan.id
                )

                try await uploadXCTestProducts(
                    xctestproductsPath,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    reference: reference,
                    shardPlan: shardPlan,
                    uploadId: uploadId
                )
            }
            try await shardMatrixOutputService.output(shardPlan)

            return shardPlan
        }

        /// Per-module recovery attempts when the bulk enumeration pass omits a module declared in the
        /// `.xctestrun`. `xcodebuild -enumerate-tests` boots the test bundles to discover their tests and
        /// can intermittently return an incomplete set (e.g. a slow UI-test host), silently dropping a
        /// module — and therefore its tests — from a suite-granularity plan. Re-enumerating just the
        /// missing module in isolation recovers it without redoing the whole (expensive) pass.
        private static let maxModuleRecoveryAttempts = 2

        /// Enumerates the test suites in the built test products for suite-granularity sharding.
        ///
        /// The module universe is taken from the `.xctestrun` (`expectedModules`), which is deterministic.
        /// Suite discovery via `xcodebuild -enumerate-tests` is not — a flaky bulk pass can omit modules —
        /// so to keep the plan complete we:
        ///
        /// 1. Run one bulk enumeration pass.
        /// 2. Re-enumerate, per module, any `expectedModules` the bulk pass never reported (isolating a
        ///    slow/failing target instead of redoing all of them).
        /// 3. Reconcile against `expectedModules`:
        ///    - modules with suites are sharded at suite granularity;
        ///    - modules that enumerated but reported *no* tests are genuinely empty and excluded;
        ///    - modules that never enumerated at all are emitted as whole-module units (see
        ///      `ShardConstants.wholeModuleSuiteSentinel`) so they still run whole, rather than being
        ///      silently dropped from the plan.
        private func enumerateTestSuites(
            testProductsPath: AbsolutePath,
            destination: String?,
            expectedModules: [String]
        ) async throws -> [String] {
            let expectedModules = Set(expectedModules)
            var suitesByModule: [String: Set<String>] = [:]
            var enumeratedModules: Set<String> = []

            func ingest(_ targets: [XCTestRun.TestTarget]) {
                for target in targets {
                    enumeratedModules.insert(target.blueprintName)
                    let suites = target.onlyTestIdentifiers ?? []
                    guard !suites.isEmpty else { continue }
                    suitesByModule[target.blueprintName, default: []].formUnion(suites)
                }
            }

            // 1. Bulk pass.
            ingest(try await enumerate(testProductsPath: testProductsPath, destination: destination, onlyTesting: []))

            // 2. Per-target recovery for modules the bulk pass never reported.
            let missingAfterBulk = expectedModules.subtracting(enumeratedModules).sorted()
            if !missingAfterBulk.isEmpty {
                Logger.current.warning(
                    "Test enumeration reported \(expectedModules.intersection(enumeratedModules).count) of \(expectedModules.count) module(s); recovering \(missingAfterBulk.count) module(s) individually to avoid dropping tests from the shard plan."
                )
                for module in missingAfterBulk {
                    for _ in 1 ... Self.maxModuleRecoveryAttempts {
                        ingest(try await enumerate(
                            testProductsPath: testProductsPath,
                            destination: destination,
                            onlyTesting: [module]
                        ))
                        if enumeratedModules.contains(module) { break }
                    }
                }
            }

            // 3. Reconcile against the deterministic `.xctestrun` universe.
            let unenumerableModules = expectedModules.subtracting(enumeratedModules).sorted()
            let emptyModules = expectedModules
                .intersection(enumeratedModules)
                .subtracting(suitesByModule.keys)
                .sorted()

            if !emptyModules.isEmpty {
                Logger.current.debug(
                    "\(emptyModules.count) module(s) enumerated no tests and are excluded as empty: \(emptyModules.joined(separator: ", "))."
                )
            }
            if !unenumerableModules.isEmpty {
                Logger.current.warning(
                    "\(unenumerableModules.count) module(s) could not be enumerated after recovery and will run whole (module-level) to avoid dropping tests: \(unenumerableModules.joined(separator: ", "))."
                )
            }

            var units = suitesByModule.flatMap { module, suites in suites.map { "\(module)/\($0)" } }
            units += unenumerableModules.map { "\($0)/\(ShardConstants.wholeModuleSuiteSentinel)" }
            return units.sorted()
        }

        /// Runs a single enumeration pass. A failed *isolated recovery* pass (`onlyTesting` non-empty) is
        /// non-fatal — the module stays unenumerable and is handled by the whole-module backstop — while a
        /// failed *bulk* pass is fatal, since there would be nothing to shard.
        private func enumerate(
            testProductsPath: AbsolutePath,
            destination: String?,
            onlyTesting: [String]
        ) async throws -> [XCTestRun.TestTarget] {
            do {
                return try await xcTestEnumerator.enumerateTests(
                    testProductsPath: testProductsPath,
                    destination: destination,
                    onlyTesting: onlyTesting
                )
            } catch {
                if onlyTesting.isEmpty { throw error }
                Logger.current.debug(
                    "Per-target enumeration of \(onlyTesting.joined(separator: ", ")) failed: \(error.localizedDescription)"
                )
                return []
            }
        }

        private func uploadXCTestProducts(
            _ xctestproductsPath: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            reference: String,
            shardPlan: Components.Schemas.ShardPlan,
            uploadId: String
        ) async throws {
            Logger.current.debug("Uploading test products bundle...")
            let archiveDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard-archive")
            let archivePath = archiveDirectory.appending(component: "bundle.aar")
            try await archiveXCTestProducts(xctestproductsPath, to: archivePath)
            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: archivePath,
                generateUploadURL: { part in
                    try await multipartUploadGenerateURLShardsService.generateUploadURL(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        shardPlanId: shardPlan.id,
                        reference: reference,
                        uploadId: uploadId,
                        partNumber: part.number
                    )
                },
                updateProgress: { progress in
                    Logger.current.debug("Upload progress: \(Int(progress * 100))%")
                }
            )

            try await multipartUploadCompleteShardsService.completeUpload(
                fullHandle: fullHandle,
                serverURL: serverURL,
                shardPlanId: shardPlan.id,
                reference: reference,
                uploadId: uploadId,
                parts: parts.map { (partNumber: $0.partNumber, etag: $0.etag) }
            )

            Logger.current.debug("Upload complete. Shard matrix ready.")
        }

        /// Creates a compressed archive of the test products bundle, excluding dSYMs
        /// to reduce upload size.
        private func archiveXCTestProducts(_ xctestproductsPath: AbsolutePath, to archivePath: AbsolutePath) async throws {
            if try await !fileSystem.exists(archivePath.parentDirectory, isDirectory: true) {
                try await fileSystem.makeDirectory(at: archivePath.parentDirectory)
            }
            try await appleArchiver.compress(
                directory: xctestproductsPath,
                to: archivePath,
                excludePatterns: [".dSYM"]
            )
        }
    }
#endif
