#if os(macOS)
    import FileSystem
    import Foundation
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
            schemes: [String],
            reference: String?,
            shardGranularity: ShardGranularity,
            shardMin: Int?,
            shardMax: Int?,
            shardTotal: Int?,
            shardMaxDuration: Int?,
            fullHandle: String,
            serverURL: URL
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
                return "Cannot derive a shard plan ID. Make sure you are running in a supported CI environment."
            case let .xcTestRunNotFound(path):
                return "No .xctestrun file found in \(path.pathString)"
            }
        }
    }

    public struct ShardPlanService: ShardPlanServicing {
        private let xcTestEnumerator: XCTestEnumerating
        private let createShardPlanService: CreateShardPlanServicing
        private let multipartUploadArtifactService: MultipartUploadArtifactServicing
        private let multipartUploadGenerateURLShardsService: MultipartUploadGenerateURLShardsServicing
        private let multipartUploadCompleteShardsService: MultipartUploadCompleteShardsServicing
        private let ciController: CIControlling
        private let fileSystem: FileSysteming
        private let fileArchiver: FileArchivingFactorying

        public init(
            xcTestEnumerator: XCTestEnumerating = XCTestEnumerator(),
            createShardPlanService: CreateShardPlanServicing = CreateShardPlanService(),
            multipartUploadArtifactService: MultipartUploadArtifactServicing = MultipartUploadArtifactService(),
            multipartUploadGenerateURLShardsService: MultipartUploadGenerateURLShardsServicing =
                MultipartUploadGenerateURLShardsService(),
            multipartUploadCompleteShardsService: MultipartUploadCompleteShardsServicing =
                MultipartUploadCompleteShardsService(),
            ciController: CIControlling = CIController(),
            fileSystem: FileSysteming = FileSystem(),
            fileArchiver: FileArchivingFactorying = FileArchivingFactory()
        ) {
            self.xcTestEnumerator = xcTestEnumerator
            self.createShardPlanService = createShardPlanService
            self.multipartUploadArtifactService = multipartUploadArtifactService
            self.multipartUploadGenerateURLShardsService = multipartUploadGenerateURLShardsService
            self.multipartUploadCompleteShardsService = multipartUploadCompleteShardsService
            self.ciController = ciController
            self.fileSystem = fileSystem
            self.fileArchiver = fileArchiver
        }

        public func plan(
            xctestproductsPath: AbsolutePath,
            schemes: [String],
            reference: String?,
            shardGranularity: ShardGranularity,
            shardMin: Int?,
            shardMax: Int?,
            shardTotal: Int?,
            shardMaxDuration: Int?,
            fullHandle: String,
            serverURL: URL
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
                var allSuites: [String] = []
                for scheme in schemes {
                    let suitesMap = try await xcTestEnumerator.enumerateTests(
                        testProductsPath: xctestproductsPath,
                        scheme: scheme,
                        destination: nil
                    )
                    allSuites += suitesMap.flatMap { $0.value }
                }
                testSuites = allSuites
            }

            Logger.current.debug("Creating shard plan '\(reference)' with \(modules.count) test modules...")

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
                shardGranularity: shardGranularity
            )

            Logger.current.info("Shard plan created: \(shardPlan.shard_count) shards")

            Logger.current.debug("Uploading test products bundle...")
            let archivePath = try await fileArchiver
                .makeFileArchiver(for: [xctestproductsPath])
                .zip(name: "bundle.xctestproducts")
            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: archivePath,
                generateUploadURL: { part in
                    try await multipartUploadGenerateURLShardsService.generateUploadURL(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        reference: reference,
                        uploadId: shardPlan.upload_id,
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
                uploadId: shardPlan.upload_id,
                parts: parts.map { (partNumber: $0.partNumber, etag: $0.etag) }
            )

            Logger.current.debug("Upload complete. Shard matrix ready.")
            try await outputShardMatrix(shardPlan)

            return shardPlan
        }

        private func outputShardMatrix(_ shardPlan: Components.Schemas.ShardPlan) async throws {
            for shard in shardPlan.shards {
                Logger.current
                    .info(
                        "  Shard \(shard.index): \(shard.test_targets.joined(separator: ", ")) (~\(shard.estimated_duration_ms)ms)"
                    )
            }

            let indices = (0 ..< shardPlan.shard_count).map { $0 }

            if let githubOutputPath = Environment.current.variables["GITHUB_OUTPUT"] {
                let outputPath = try AbsolutePath(validating: githubOutputPath)
                let matrixJSON = "{\"shard\":\(indices)}"
                let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
                try await fileSystem.writeText(
                    existing + "matrix=\(matrixJSON)\n",
                    at: outputPath,
                    options: [.overwrite]
                )
                Logger.current.debug("GitHub Actions matrix output written.")
            } else {
                let currentDirectory = try await Environment.current.currentWorkingDirectory()
                let outputPath = currentDirectory.appending(component: ".tuist-shard-matrix.json")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try await fileSystem.writeAsJSON(shardPlan, at: outputPath, encoder: encoder)
                Logger.current.debug("Shard matrix written to \(outputPath.pathString)")
            }
        }
    }
#endif
