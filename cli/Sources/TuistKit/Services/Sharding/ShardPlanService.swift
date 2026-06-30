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
        case modulesFailedToEnumerate([String])

        public var errorDescription: String? {
            switch self {
            case .noTestModulesFound:
                return "No test modules found in the .xctestproducts bundle."
            case .cannotDeriveSessionId:
                return
                    "Cannot derive a shard plan reference. Pass --shard-reference explicitly or run in a supported CI environment (GitHub Actions, GitLab CI, CircleCI, Buildkite, Codemagic)."
            case let .xcTestRunNotFound(path):
                return "No .xctestrun file found in \(path.pathString)"
            case let .modulesFailedToEnumerate(modules):
                return
                    "Could not enumerate tests for \(modules.count) module(s) after retries: \(modules.joined(separator: ", ")). Ensure these test targets build and run, or remove them from the test plan."
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
        /// Suite discovery via `xcodebuild -enumerate-tests` is not: it boots the test bundles, so a module
        /// can be reported either missing or — more insidiously — *present-but-empty* when its target fails to
        /// boot (e.g. a flaky simulator under load). Both look identical to a genuinely empty target except
        /// that xcodebuild records the failure in the enumeration's `errors`. To keep the plan complete we:
        ///
        /// 1. Run one bulk enumeration pass.
        /// 2. Re-enumerate, in isolation, every `expectedModules` the bulk pass produced *no suites* for —
        ///    whether missing entirely or present-but-empty. An isolated pass disambiguates: finding suites
        ///    recovers the module; reporting it present-but-empty with no errors confirms it is genuinely
        ///    empty; anything else (errors, or still missing) is a real failure.
        /// 3. Reconcile against `expectedModules`:
        ///    - modules with suites are sharded at suite granularity;
        ///    - modules confirmed genuinely empty are excluded;
        ///    - any remaining module failed to enumerate and throws, rather than being silently dropped.
        private func enumerateTestSuites(
            testProductsPath: AbsolutePath,
            destination: String?,
            expectedModules: [String]
        ) async throws -> [String] {
            let expectedModules = Set(expectedModules)
            var suitesByModule: [String: Set<String>] = [:]

            func ingest(_ enumeration: XCTestEnumeration) {
                for target in enumeration.targets {
                    let suites = target.onlyTestIdentifiers ?? []
                    guard !suites.isEmpty else { continue }
                    suitesByModule[target.blueprintName, default: []].formUnion(suites)
                }
            }

            // 1. Bulk pass.
            ingest(try await enumerate(testProductsPath: testProductsPath, destination: destination, onlyTesting: []))

            // 2. Recovery for every expected module the bulk pass produced no suites for. A present-but-empty
            //    target is ambiguous (genuinely empty vs. failed to boot), so we re-enumerate it in isolation
            //    and let that pass arbitrate.
            var confirmedEmptyModules: Set<String> = []
            var failureDetailByModule: [String: String] = [:]
            let modulesNeedingRecovery = expectedModules.filter { suitesByModule[$0] == nil }.sorted()
            if !modulesNeedingRecovery.isEmpty {
                Logger.current.warning(
                    "Test enumeration produced suites for \(suitesByModule.count) of \(expectedModules.count) module(s); re-enumerating \(modulesNeedingRecovery.count) module(s) individually to avoid dropping tests from the shard plan."
                )
                for module in modulesNeedingRecovery {
                    for _ in 1 ... Self.maxModuleRecoveryAttempts {
                        let enumeration = try await enumerate(
                            testProductsPath: testProductsPath,
                            destination: destination,
                            onlyTesting: [module]
                        )
                        ingest(enumeration)
                        if suitesByModule[module] != nil { break }
                        if enumeration.errors.isEmpty,
                           enumeration.targets.contains(where: { $0.blueprintName == module })
                        {
                            // Booted and enumerated cleanly, it simply has no tests.
                            confirmedEmptyModules.insert(module)
                            break
                        }
                        failureDetailByModule[module] = enumeration.errors.first
                            ?? "the module was not reported by `xcodebuild -enumerate-tests`"
                    }
                }
            }

            // 3. Reconcile against the deterministic `.xctestrun` universe. A module we could neither find
            // suites for nor confirm as genuinely empty failed to enumerate (e.g. a target that won't boot),
            // so fail loudly — with the underlying xcodebuild error — rather than silently dropping its tests.
            let failedModules = expectedModules
                .filter { suitesByModule[$0] == nil }
                .subtracting(confirmedEmptyModules)
                .sorted()
            guard failedModules.isEmpty else {
                let details = failedModules.compactMap { module in
                    failureDetailByModule[module].map { "\(module): \($0)" }
                }
                if !details.isEmpty {
                    Logger.current.error(
                        "Test enumeration failed for \(failedModules.count) module(s):\n\(details.joined(separator: "\n"))"
                    )
                }
                throw ShardPlanServiceError.modulesFailedToEnumerate(failedModules)
            }

            if !confirmedEmptyModules.isEmpty {
                Logger.current.debug(
                    "\(confirmedEmptyModules.count) module(s) enumerated no tests and are excluded as empty: \(confirmedEmptyModules.sorted().joined(separator: ", "))."
                )
            }

            return suitesByModule
                .flatMap { module, suites in suites.map { "\(module)/\($0)" } }
                .sorted()
        }

        /// Runs a single enumeration pass. A failed *bulk* pass is fatal — there would be nothing to shard. A
        /// failed *isolated recovery* pass (`onlyTesting` non-empty) is non-fatal but is surfaced as an
        /// `errors` entry for the module being recovered, so the reconcile step fails loudly instead of
        /// silently dropping it.
        private func enumerate(
            testProductsPath: AbsolutePath,
            destination: String?,
            onlyTesting: [String]
        ) async throws -> XCTestEnumeration {
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
                return XCTestEnumeration(targets: [], errors: [error.localizedDescription])
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
