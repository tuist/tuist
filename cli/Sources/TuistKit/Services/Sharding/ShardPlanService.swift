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
            scheme: String,
            planId: String?,
            granularity: ShardGranularity,
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
        case xctestrunNotFound(AbsolutePath)

        public var errorDescription: String? {
            switch self {
            case .noTestModulesFound:
                return "No test modules found in the .xctestproducts bundle."
            case .cannotDeriveSessionId:
                return "Cannot derive a shard plan ID. Make sure you are running in a supported CI environment."
            case let .xctestrunNotFound(path):
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
        private let generateShardXctestrunUploadURLService: GenerateShardXctestrunUploadURLServicing
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
            generateShardXctestrunUploadURLService: GenerateShardXctestrunUploadURLServicing =
                GenerateShardXctestrunUploadURLService(),
            ciController: CIControlling = CIController(),
            fileSystem: FileSysteming = FileSystem(),
            fileArchiver: FileArchivingFactorying = FileArchivingFactory()
        ) {
            self.xcTestEnumerator = xcTestEnumerator
            self.createShardPlanService = createShardPlanService
            self.multipartUploadArtifactService = multipartUploadArtifactService
            self.multipartUploadGenerateURLShardsService = multipartUploadGenerateURLShardsService
            self.multipartUploadCompleteShardsService = multipartUploadCompleteShardsService
            self.generateShardXctestrunUploadURLService = generateShardXctestrunUploadURLService
            self.ciController = ciController
            self.fileSystem = fileSystem
            self.fileArchiver = fileArchiver
        }

        public func plan(
            xctestproductsPath: AbsolutePath,
            scheme: String,
            planId: String?,
            granularity: ShardGranularity,
            shardMin: Int?,
            shardMax: Int?,
            shardTotal: Int?,
            shardMaxDuration: Int?,
            fullHandle: String,
            serverURL: URL
        ) async throws -> Components.Schemas.ShardPlan {
            guard let planId = planId ?? ciController.ciInfo()?.shardPlanId else {
                throw ShardPlanServiceError.cannotDeriveSessionId
            }

            guard let xctestrunPath = try await fileSystem
                .glob(directory: xctestproductsPath, include: ["**/*.xctestrun"])
                .collect()
                .first
            else {
                throw ShardPlanServiceError.xctestrunNotFound(xctestproductsPath)
            }
            let xctestrun: XCTestRun = try await fileSystem.readPlistFile(at: xctestrunPath)
            let modules = xctestrun.testModules

            guard !modules.isEmpty else {
                throw ShardPlanServiceError.noTestModulesFound
            }

            var testSuites: [String]?
            if granularity == .suite {
                let suitesMap = try await xcTestEnumerator.enumerateTests(
                    testProductsPath: xctestproductsPath,
                    scheme: scheme,
                    destination: nil
                )
                testSuites = suitesMap.flatMap { $0.value }
            }

            Logger.current.info("Creating shard plan '\(planId)' with \(modules.count) test modules...")

            let shardPlan = try await createShardPlanService.createShardPlan(
                fullHandle: fullHandle,
                serverURL: serverURL,
                planId: planId,
                modules: granularity == .module ? modules : nil,
                testSuites: testSuites,
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration,
                granularity: granularity.rawValue
            )

            Logger.current.info("Shard plan created: \(shardPlan.shard_count) shards")

            let xctestrunUploadURL = try await generateShardXctestrunUploadURLService.generateURL(
                fullHandle: fullHandle,
                serverURL: serverURL,
                planId: planId
            )

            let xctestrunData = try Data(contentsOf: URL(fileURLWithPath: xctestrunPath.pathString))
            var request = URLRequest(url: URL(string: xctestrunUploadURL)!)
            request.httpMethod = "PUT"
            request.httpBody = xctestrunData
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, xctestrunResponse) = try await URLSession.shared.data(for: request)
            if let httpResponse = xctestrunResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
                Logger.current.warning("Failed to upload .xctestrun file (status: \(httpResponse.statusCode))")
            }

            Logger.current.info("Uploading test products bundle...")
            let archivePath = try await fileArchiver
                .makeFileArchiver(for: [xctestproductsPath])
                .zip(name: "bundle.xctestproducts")
            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: archivePath,
                generateUploadURL: { part in
                    try await multipartUploadGenerateURLShardsService.generateUploadURL(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        planId: planId,
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
                planId: planId,
                uploadId: shardPlan.upload_id,
                parts: parts.map { (partNumber: $0.partNumber, etag: $0.etag) }
            )

            Logger.current.info("Upload complete. Shard matrix ready.")
            outputShardMatrix(shardPlan)

            return shardPlan
        }

        private func outputShardMatrix(_ shardPlan: Components.Schemas.ShardPlan) {
            for shard in shardPlan.shards {
                Logger.current
                    .info(
                        "  Shard \(shard.index): \(shard.test_targets.joined(separator: ", ")) (~\(shard.estimated_duration_ms)ms)"
                    )
            }

            let indices = (0 ..< shardPlan.shard_count).map { $0 }

            if let githubOutputPath = Environment.current.variables["GITHUB_OUTPUT"],
               let handle = FileHandle(forWritingAtPath: githubOutputPath)
            {
                let matrixJSON = "{\"shard\":\(indices)}"
                handle.seekToEndOfFile()
                handle.write(Data("matrix=\(matrixJSON)\n".utf8))
                handle.closeFile()
                Logger.current.info("GitHub Actions matrix output written.")
            } else {
                let matrixData: [String: Any] = [
                    "plan_id": shardPlan.session_id,
                    "shard_count": shardPlan.shard_count,
                    "shards": shardPlan.shards.map { shard in
                        [
                            "index": shard.index,
                            "test_targets": shard.test_targets,
                            "estimated_duration_ms": shard.estimated_duration_ms,
                        ] as [String: Any]
                    },
                ]
                let jsonData = try? JSONSerialization.data(
                    withJSONObject: matrixData,
                    options: [.prettyPrinted, .sortedKeys]
                )
                let outputPath = ".tuist-shard-matrix.json"
                if let jsonData {
                    FileManager.default.createFile(atPath: outputPath, contents: jsonData)
                    Logger.current.info("Shard matrix written to \(outputPath)")
                }
            }
        }
    }
#endif
