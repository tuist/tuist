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
            shardMatrixOutputService: ShardMatrixOutputServicing = ShardMatrixOutputService()
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
                let destination = inferDestination(from: xcTestRunPath)
                var allSuites: [String] = []
                for scheme in schemes {
                    let targets = try await xcTestEnumerator.enumerateTests(
                        testProductsPath: xctestproductsPath,
                        scheme: scheme,
                        destination: destination
                    )
                    allSuites += targets.flatMap { $0.onlyTestIdentifiers ?? [] }
                }
                testSuites = allSuites
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
                shardGranularity: shardGranularity
            )

            Logger.current.notice("Shard plan created: \(shardPlan.shard_count) shards", metadata: .section)

            let uploadId = try await startShardUploadService.startUpload(
                fullHandle: fullHandle,
                serverURL: serverURL,
                reference: reference
            )

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
        private func inferDestination(from xcTestRunPath: AbsolutePath) -> String? {
            let binariesPath = xcTestRunPath
                .parentDirectory // Tests/0/
                .parentDirectory // Tests/
                .parentDirectory // .xctestproducts/
                .appending(components: "Binaries", "0")

            guard let firstDir = try? FileManager.default.contentsOfDirectory(atPath: binariesPath.pathString).first
            else { return nil }

            if firstDir.contains("iphonesimulator") {
                return "platform=iOS Simulator,name=iPhone"
            } else if firstDir.contains("appletvsimulator") {
                return "platform=tvOS Simulator,name=Apple TV"
            } else if firstDir.contains("watchsimulator") {
                return "platform=watchOS Simulator,name=Apple Watch"
            } else if firstDir.contains("xrsimulator") {
                return "platform=visionOS Simulator,name=Apple Vision Pro"
            } else {
                return "platform=macOS"
            }
        }
    }
#endif
