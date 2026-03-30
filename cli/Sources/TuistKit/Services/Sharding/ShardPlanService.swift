#if os(macOS)
    import AppleArchive
    import FileSystem
    import Foundation
    import System
    import Mockable
    import Path
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
            buildRunId: String?
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
            buildRunId: String?
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
                let targets = try await xcTestEnumerator.enumerateTests(
                    testProductsPath: xctestproductsPath,
                    destination: destination
                )
                testSuites = targets.flatMap { target in
                    (target.onlyTestIdentifiers ?? []).map { "\(target.blueprintName)/\($0)" }
                }
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

            let uploadId = try await startShardUploadService.startUpload(
                fullHandle: fullHandle,
                serverURL: serverURL,
                reference: reference
            )

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
                reference: reference,
                uploadId: uploadId,
                parts: parts.map { (partNumber: $0.partNumber, etag: $0.etag) }
            )

            Logger.current.debug("Upload complete. Shard matrix ready.")
            try await shardMatrixOutputService.output(shardPlan)

            return shardPlan
        }

        /// Creates a compressed archive of the test products bundle, stripping files not needed for test execution
        /// (dSYMs, .swiftmodule directories) to significantly reduce upload size.
        private func archiveXCTestProducts(_ xctestproductsPath: AbsolutePath, to archivePath: AbsolutePath) async throws {
            try await fileSystem.runInTemporaryDirectory(prefix: "tuist-shard-stripped") { strippedPath in
                let strippedProductsPath = strippedPath.appending(component: xctestproductsPath.basename)
                try await fileSystem.copy(xctestproductsPath, to: strippedProductsPath)

                // Remove .dSYM and .swiftmodule directories which are only needed for
                // symbolication/compilation, not for running tests.
                let stripPatterns = ["**/*.dSYM", "**/*.swiftmodule"]
                for pattern in stripPatterns {
                    for try await path in try fileSystem.glob(directory: strippedProductsPath, include: [pattern]) {
                        try await fileSystem.remove(path)
                    }
                }

                try await appleArchiver.compress(directory: strippedProductsPath, to: archivePath)
            }
        }
    }
#endif
