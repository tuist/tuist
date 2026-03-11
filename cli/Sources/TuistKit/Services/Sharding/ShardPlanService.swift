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
            shardConfiguration: ShardConfiguration,
            fullHandle: String,
            serverURL: URL
        ) async throws -> ServerShardSession
    }

    public enum ShardPlanServiceError: LocalizedError, Equatable {
        case noTestModulesFound
        case cannotDeriveSessionId

        public var errorDescription: String? {
            switch self {
            case .noTestModulesFound:
                return "No test modules found in the .xctestproducts bundle."
            case .cannotDeriveSessionId:
                return "Cannot derive a shard session ID. Make sure you are running in a supported CI environment."
            }
        }
    }

    public struct ShardPlanService: ShardPlanServicing {
        private let xcTestRunParser: XCTestRunParsing
        private let xcTestEnumerator: XCTestEnumerating
        private let createShardSessionService: CreateShardSessionServicing
        private let multipartUploadArtifactService: MultipartUploadArtifactServicing
        private let multipartUploadGenerateURLShardsService: MultipartUploadGenerateURLShardsServicing
        private let multipartUploadCompleteShardsService: MultipartUploadCompleteShardsServicing
        private let generateShardXctestrunUploadURLService: GenerateShardXctestrunUploadURLServicing
        private let ciController: CIControlling
        private let fileSystem: FileSysteming

        public init(
            xcTestRunParser: XCTestRunParsing = XCTestRunParser(),
            xcTestEnumerator: XCTestEnumerating = XCTestEnumerator(),
            createShardSessionService: CreateShardSessionServicing = CreateShardSessionService(),
            multipartUploadArtifactService: MultipartUploadArtifactServicing = MultipartUploadArtifactService(),
            multipartUploadGenerateURLShardsService: MultipartUploadGenerateURLShardsServicing =
                MultipartUploadGenerateURLShardsService(),
            multipartUploadCompleteShardsService: MultipartUploadCompleteShardsServicing =
                MultipartUploadCompleteShardsService(),
            generateShardXctestrunUploadURLService: GenerateShardXctestrunUploadURLServicing =
                GenerateShardXctestrunUploadURLService(),
            ciController: CIControlling = CIController(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.xcTestRunParser = xcTestRunParser
            self.xcTestEnumerator = xcTestEnumerator
            self.createShardSessionService = createShardSessionService
            self.multipartUploadArtifactService = multipartUploadArtifactService
            self.multipartUploadGenerateURLShardsService = multipartUploadGenerateURLShardsService
            self.multipartUploadCompleteShardsService = multipartUploadCompleteShardsService
            self.generateShardXctestrunUploadURLService = generateShardXctestrunUploadURLService
            self.ciController = ciController
            self.fileSystem = fileSystem
        }

        public func plan(
            xctestproductsPath: AbsolutePath,
            scheme: String,
            shardConfiguration: ShardConfiguration,
            fullHandle: String,
            serverURL: URL
        ) async throws -> ServerShardSession {
            guard let sessionId = ciController.ciInfo()?.shardSessionId else {
                throw ShardPlanServiceError.cannotDeriveSessionId
            }

            let xctestrunPath = try xcTestRunParser.findXCTestRunPath(in: xctestproductsPath)
            let modules = try xcTestRunParser.parseTestModules(xctestrunPath: xctestrunPath)

            guard !modules.isEmpty else {
                throw ShardPlanServiceError.noTestModulesFound
            }

            var testSuites: [String]?
            if shardConfiguration.granularity == .suite {
                let suitesMap = try await xcTestEnumerator.enumerateTests(
                    testProductsPath: xctestproductsPath,
                    scheme: scheme,
                    destination: nil
                )
                testSuites = suitesMap.flatMap { $0.value }
            }

            Logger.current.info("Creating shard session '\(sessionId)' with \(modules.count) test modules...")

            let session = try await createShardSessionService.createShardSession(
                fullHandle: fullHandle,
                serverURL: serverURL,
                sessionId: sessionId,
                modules: shardConfiguration.granularity == .module ? modules : nil,
                testSuites: testSuites,
                shardMin: shardConfiguration.shardMin,
                shardMax: shardConfiguration.shardMax,
                shardTotal: shardConfiguration.shardTotal,
                shardMaxDuration: shardConfiguration.shardMaxDuration,
                granularity: shardConfiguration.granularity.rawValue
            )

            Logger.current.info("Shard session created: \(session.shardCount) shards")

            let xctestrunUploadURL = try await generateShardXctestrunUploadURLService.generateURL(
                fullHandle: fullHandle,
                serverURL: serverURL,
                sessionId: sessionId
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
            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: xctestproductsPath,
                generateUploadURL: { part in
                    try await multipartUploadGenerateURLShardsService.generateUploadURL(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        sessionId: sessionId,
                        uploadId: session.uploadId,
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
                sessionId: sessionId,
                uploadId: session.uploadId,
                parts: parts
            )

            Logger.current.info("Upload complete. Shard matrix ready.")
            outputShardMatrix(session: session)

            return session
        }

        private func outputShardMatrix(session: ServerShardSession) {
            let indices = (0 ..< session.shardCount).map { $0 }

            if let githubOutputPath = Environment.current.variables["GITHUB_OUTPUT"],
               let handle = FileHandle(forWritingAtPath: githubOutputPath)
            {
                let matrixJSON = "{\"shard\":\(indices)}"
                handle.seekToEndOfFile()
                handle.write(Data("matrix=\(matrixJSON)\n".utf8))
                handle.closeFile()
                Logger.current.info("GitHub Actions matrix output written.")
            }

            for shard in session.shards {
                Logger.current
                    .info(
                        "  Shard \(shard.index): \(shard.testTargets.joined(separator: ", ")) (~\(shard.estimatedDurationMs)ms)"
                    )
            }
        }
    }
#endif
