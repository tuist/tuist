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
        /// Cap on concurrent artifact (shared + per-module) compress+upload operations, so a project
        /// with many modules doesn't spawn an unbounded number at once. Matches the URLSession
        /// per-host connection cap.
        private static let maxConcurrentArtifactUploads = 20

        private enum SplitArtifact {
            case shared
            case module(name: String, paths: [AbsolutePath])
        }

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

            // Suite-granularity plans are balanced server-side from historical per-suite timings, and the
            // catch-all shard guarantees any suite without history still runs. The client therefore no
            // longer enumerates suites by booting every test bundle on the simulator (slow and flaky on
            // large plans — it could take an hour) and sends only the module universe from the
            // deterministic `.xctestrun`.
            Logger.current.notice("Creating shard plan with \(modules.count) test module(s)", metadata: .section)

            let shardPlan = try await createShardPlanService.createShardPlan(
                fullHandle: fullHandle,
                serverURL: serverURL,
                reference: reference,
                modules: modules,
                testSuites: nil,
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
                try await uploadSplitArtifacts(
                    xctestproductsPath: xctestproductsPath,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    shardPlanId: shardPlan.id,
                    reference: reference
                )
            }
            try await shardMatrixOutputService.output(shardPlan)

            return shardPlan
        }

        /// Uploads the shard test products split so each shard downloads only what it needs: a single
        /// `shared` artifact (everything except the per-module test bundles) plus one artifact per
        /// module's `.xctest`. The server hands each shard the shared artifact plus its modules' artifacts.
        private func uploadSplitArtifacts(
            xctestproductsPath: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            shardPlanId: String,
            reference: String
        ) async throws {
            Logger.current.debug("Uploading test products artifacts...")

            let archiveDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-shard-archive")
            let xctestPaths = try await fileSystem.glob(directory: xctestproductsPath, include: ["**/*.xctest"])
                .collect()
                .sorted(by: { $0.pathString < $1.pathString })
            let moduleArtifacts = Dictionary(grouping: xctestPaths, by: \.basenameWithoutExt)
                .map { module, paths in (name: module, paths: paths.sorted(by: { $0.pathString < $1.pathString })) }
                .sorted(by: { $0.name < $1.name })
                .map { SplitArtifact.module(name: $0.name, paths: $0.paths) }

            // Each artifact (the shared bundle plus one per module) is an independent compress + upload;
            // run them concurrently, capped so a project with many modules doesn't oversubscribe the host.
            let artifacts: [SplitArtifact] = [.shared] + moduleArtifacts
            _ = try await artifacts.concurrentMap(maxConcurrentTasks: Self.maxConcurrentArtifactUploads) { artifact in
                switch artifact {
                case .shared:
                    let sharedArchive = archiveDirectory.appending(component: "shared.aar")
                    // ".xctest/" (with the trailing slash) excludes the per-module test bundles' contents
                    // without also dropping the sibling ".xctestrun" — excludePatterns is a substring match,
                    // and ".xctestrun" contains ".xctest". The .xctestrun must stay in the shared artifact.
                    try await appleArchiver.compress(
                        directory: xctestproductsPath,
                        to: sharedArchive,
                        excludePatterns: [".dSYM", ".xctest/"]
                    )
                    try await uploadArtifact(
                        archivePath: sharedArchive,
                        artifact: "shared",
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        shardPlanId: shardPlanId,
                        reference: reference
                    )
                case let .module(module, xctestPaths):
                    let moduleArchive = archiveDirectory.appending(component: "\(module).aar")
                    try await archiveModuleProducts(xctestPaths, productsPath: xctestproductsPath, to: moduleArchive)
                    try await uploadArtifact(
                        archivePath: moduleArchive,
                        artifact: "module:\(module)",
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        shardPlanId: shardPlanId,
                        reference: reference
                    )
                }
            }

            Logger.current.debug("Upload complete. Shard matrix ready.")
        }

        private func uploadArtifact(
            archivePath: AbsolutePath,
            artifact: String,
            fullHandle: String,
            serverURL: URL,
            shardPlanId: String,
            reference: String
        ) async throws {
            let uploadId = try await startShardUploadService.startUpload(
                fullHandle: fullHandle,
                serverURL: serverURL,
                shardPlanId: shardPlanId,
                reference: reference,
                artifact: artifact
            )
            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: archivePath,
                generateUploadURL: { part in
                    try await multipartUploadGenerateURLShardsService.generateUploadURL(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        shardPlanId: shardPlanId,
                        reference: reference,
                        uploadId: uploadId,
                        partNumber: part.number,
                        artifact: artifact
                    )
                },
                updateProgress: { progress in
                    Logger.current.debug("Upload progress (\(artifact)): \(Int(progress * 100))%")
                }
            )
            try await multipartUploadCompleteShardsService.completeUpload(
                fullHandle: fullHandle,
                serverURL: serverURL,
                shardPlanId: shardPlanId,
                reference: reference,
                uploadId: uploadId,
                parts: parts.map { (partNumber: $0.partNumber, etag: $0.etag) },
                artifact: artifact
            )
        }

        /// Archives a module's `.xctest` bundle(s) preserving their paths relative to the products
        /// root, so extracting alongside the shared artifact reconstructs the original layout.
        /// The `.xctest` bundles are read in place — a project with hundreds of modules would
        /// otherwise copy every (multi-hundred-MB) test bundle into a staging directory before
        /// compressing it.
        private func archiveModuleProducts(
            _ xctestPaths: [AbsolutePath],
            productsPath: AbsolutePath,
            to archivePath: AbsolutePath
        ) async throws {
            try await appleArchiver.compress(
                subdirectories: xctestPaths,
                relativeTo: productsPath,
                to: archivePath
            )
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
