#if os(macOS)
    import FileSystem
    import Foundation
    import Mockable
    import Path
    import TuistCI
    import TuistCore
    import TuistLogging
    import TuistServer
    import TuistSupport

    public struct ShardExecuteResult {
        public let testProductsPath: AbsolutePath
        public let testTargets: [String]
        public let selectiveTestingGraph: SelectiveTestingGraph?
    }

    @Mockable
    public protocol ShardExecuteServicing {
        func execute(
            shardIndex: Int,
            scheme: String,
            fullHandle: String,
            serverURL: URL,
            outputPath: AbsolutePath
        ) async throws -> ShardExecuteResult
    }

    public enum ShardExecuteServiceError: LocalizedError, Equatable {
        case cannotDeriveSessionId
        case downloadFailed(String)
        case unzipFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotDeriveSessionId:
                return "Cannot derive a shard plan ID. Make sure you are running in a supported CI environment."
            case let .downloadFailed(message):
                return "Failed to download shard artifacts: \(message)"
            case let .unzipFailed(message):
                return "Failed to unzip shard bundle: \(message)"
            }
        }
    }

    public struct ShardExecuteService: ShardExecuteServicing {
        private let getShardAssignmentService: GetShardAssignmentServicing
        private let ciController: CIControlling
        private let fileSystem: FileSysteming

        public init(
            getShardAssignmentService: GetShardAssignmentServicing = GetShardAssignmentService(),
            ciController: CIControlling = CIController(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.getShardAssignmentService = getShardAssignmentService
            self.ciController = ciController
            self.fileSystem = fileSystem
        }

        public func execute(
            shardIndex: Int,
            scheme: String,
            fullHandle: String,
            serverURL: URL,
            outputPath: AbsolutePath
        ) async throws -> ShardExecuteResult {
            guard let planId = ciController.ciInfo()?.shardPlanId else {
                throw ShardExecuteServiceError.cannotDeriveSessionId
            }

            Logger.current.debug("Fetching shard assignment for shard \(shardIndex) in plan '\(planId)'...")

            let assignment = try await getShardAssignmentService.getShardAssignment(
                fullHandle: fullHandle,
                serverURL: serverURL,
                planId: planId,
                shardIndex: shardIndex
            )

            Logger.current.info("Shard \(shardIndex) assigned targets: \(assignment.testTargets.joined(separator: ", "))")

            let bundleZipPath = outputPath.appending(component: "\(scheme).xctestproducts.zip")
            try await downloadFile(from: assignment.bundleDownloadURL, to: bundleZipPath)
            Logger.current.debug("Downloaded test products bundle.")

            let unzippedPath = outputPath.appending(component: "unzipped")
            if try await fileSystem.exists(unzippedPath) {
                try await fileSystem.remove(unzippedPath)
            }
            try await fileSystem.makeDirectory(at: unzippedPath)
            let dittoProcess = Process()
            dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProcess.arguments = ["-x", "-k", bundleZipPath.pathString, unzippedPath.pathString]
            try dittoProcess.run()
            dittoProcess.waitUntilExit()
            guard dittoProcess.terminationStatus == 0 else {
                throw ShardExecuteServiceError.unzipFailed("ditto exited with status \(dittoProcess.terminationStatus)")
            }

            let bundlePath: AbsolutePath
            if let found = try await fileSystem.glob(directory: unzippedPath, include: ["*.xctestproducts"])
                .first(where: { _ in true })
            {
                bundlePath = found
            } else {
                bundlePath = unzippedPath
            }
            Logger.current.debug("Unzipped test products to \(bundlePath.pathString)")

            let xcTestRunPath = outputPath.appending(component: "\(scheme).xctestrun")
            try await downloadFile(from: assignment.xctestrunDownloadURL, to: xcTestRunPath)
            Logger.current.debug("Downloaded filtered .xctestrun file.")

            let targetXCTestRunPath = bundlePath.appending(component: "\(scheme).xctestrun")
            if try await fileSystem.exists(targetXCTestRunPath) {
                try await fileSystem.remove(targetXCTestRunPath)
            }
            try await fileSystem.copy(xcTestRunPath, to: targetXCTestRunPath)

            let selectiveTestingGraphPath = bundlePath.appending(component: SelectiveTestingGraph.fileName)
            var selectiveTestingGraph: SelectiveTestingGraph?
            if let data = try? Data(contentsOf: URL(fileURLWithPath: selectiveTestingGraphPath.pathString)) {
                selectiveTestingGraph = try? JSONDecoder().decode(SelectiveTestingGraph.self, from: data)
                if selectiveTestingGraph != nil {
                    Logger.current.debug("Loaded selective testing graph from test products bundle.")
                }
            }

            return ShardExecuteResult(
                testProductsPath: bundlePath,
                testTargets: assignment.testTargets,
                selectiveTestingGraph: selectiveTestingGraph
            )
        }

        private func downloadFile(from urlString: String, to path: AbsolutePath) async throws {
            guard let url = URL(string: urlString) else {
                throw ShardExecuteServiceError.downloadFailed("Invalid URL: \(urlString)")
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw ShardExecuteServiceError.downloadFailed("HTTP error downloading \(urlString)")
            }

            try data.write(to: URL(fileURLWithPath: path.pathString))
        }
    }
#endif
