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

        /// The number of times test enumeration is attempted when building a suite-granularity shard plan.
        ///
        /// `xcodebuild -enumerate-tests` boots the test bundles to discover their tests and can
        /// intermittently return an incomplete set of targets (e.g. when a simulator or UI test host is
        /// slow to launch). Suites that aren't enumerated never enter the shard plan and therefore
        /// silently never run, so we retry — unioning the results — until every module declared in the
        /// `.xctestrun` is covered.
        private static let maxEnumerationAttempts = 3

        /// Enumerates the test suites in the built test products for suite-granularity sharding.
        ///
        /// Enumeration is retried, unioning results, until it covers every module listed in the
        /// `.xctestrun` — guarding against a flaky `xcodebuild -enumerate-tests` silently dropping
        /// modules (and therefore tests) from the shard plan. Modules that never enumerate any test after
        /// every attempt are surfaced with a warning: they are usually empty test targets, but a
        /// persistent enumeration failure would otherwise silently exclude real tests.
        private func enumerateTestSuites(
            testProductsPath: AbsolutePath,
            destination: String?,
            expectedModules: [String]
        ) async throws -> [String] {
            let expectedModules = Set(expectedModules)
            var suitesByModule: [String: Set<String>] = [:]

            for attempt in 1 ... Self.maxEnumerationAttempts {
                let targets = try await xcTestEnumerator.enumerateTests(
                    testProductsPath: testProductsPath,
                    destination: destination
                )
                let coveredModulesBefore = suitesByModule.count
                for target in targets {
                    let suites = target.onlyTestIdentifiers ?? []
                    guard !suites.isEmpty else { continue }
                    suitesByModule[target.blueprintName, default: []].formUnion(suites)
                }

                // Stop as soon as every module in the `.xctestrun` has been enumerated.
                if expectedModules.isSubset(of: suitesByModule.keys) { break }
                // Otherwise stop once an attempt stops discovering new modules: retrying further won't
                // recover them (they have no enumerable tests), while keeping the retry cost bounded.
                if attempt > 1, suitesByModule.count == coveredModulesBefore { break }
                if attempt < Self.maxEnumerationAttempts {
                    Logger.current.warning(
                        "Test enumeration discovered \(suitesByModule.count) of \(expectedModules.count) test module(s); retrying to avoid dropping modules from the shard plan."
                    )
                }
            }

            let missingModules = expectedModules.subtracting(suitesByModule.keys).sorted()
            if !missingModules.isEmpty {
                Logger.current.warning(
                    "\(missingModules.count) test module(s) produced no tests during enumeration and are excluded from the suite-granularity shard plan: \(missingModules.joined(separator: ", ")). If they contain tests this is usually a flaky `xcodebuild -enumerate-tests`; re-run or use `--shard-granularity module`."
                )
            }

            return suitesByModule
                .flatMap { module, suites in suites.map { "\(module)/\($0)" } }
                .sorted()
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
