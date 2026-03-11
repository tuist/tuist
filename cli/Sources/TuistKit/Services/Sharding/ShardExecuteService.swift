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

    @Mockable
    public protocol ShardExecuteServicing {
        func execute(
            shardIndex: Int,
            scheme: String,
            fullHandle: String,
            serverURL: URL,
            outputPath: AbsolutePath
        ) async throws -> (testProductsPath: AbsolutePath, testTargets: [String])
    }

    public enum ShardExecuteServiceError: LocalizedError, Equatable {
        case cannotDeriveSessionId
        case downloadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotDeriveSessionId:
                return "Cannot derive a shard session ID. Make sure you are running in a supported CI environment."
            case let .downloadFailed(message):
                return "Failed to download shard artifacts: \(message)"
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
        ) async throws -> (testProductsPath: AbsolutePath, testTargets: [String]) {
            guard let sessionId = ciController.ciInfo()?.shardSessionId else {
                throw ShardExecuteServiceError.cannotDeriveSessionId
            }

            Logger.current.info("Fetching shard assignment for shard \(shardIndex) in session '\(sessionId)'...")

            let assignment = try await getShardAssignmentService.getShardAssignment(
                fullHandle: fullHandle,
                serverURL: serverURL,
                sessionId: sessionId,
                shardIndex: shardIndex
            )

            Logger.current.info("Shard \(shardIndex) assigned targets: \(assignment.testTargets.joined(separator: ", "))")

            let bundlePath = outputPath.appending(component: "\(scheme).xctestproducts")
            try await downloadFile(from: assignment.bundleDownloadURL, to: bundlePath)
            Logger.current.info("Downloaded test products bundle.")

            let xctestrunPath = outputPath.appending(component: "\(scheme).xctestrun")
            try await downloadFile(from: assignment.xctestrunDownloadURL, to: xctestrunPath)
            Logger.current.info("Downloaded filtered .xctestrun file.")

            let targetXctestrunPath = bundlePath.appending(component: "\(scheme).xctestrun")
            try? FileManager.default.removeItem(atPath: targetXctestrunPath.pathString)
            try FileManager.default.copyItem(
                atPath: xctestrunPath.pathString,
                toPath: targetXctestrunPath.pathString
            )

            return (testProductsPath: bundlePath, testTargets: assignment.testTargets)
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
