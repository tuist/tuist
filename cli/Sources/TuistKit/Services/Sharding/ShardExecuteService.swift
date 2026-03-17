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
                return "Cannot derive a shard session ID. Make sure you are running in a supported CI environment."
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

            let bundleZipPath = outputPath.appending(component: "\(scheme).xctestproducts.zip")
            try await downloadFile(from: assignment.bundleDownloadURL, to: bundleZipPath)
            Logger.current.info("Downloaded test products bundle.")

            let unzippedPath = outputPath.appending(component: "unzipped")
            try? FileManager.default.removeItem(atPath: unzippedPath.pathString)
            try FileManager.default.createDirectory(
                atPath: unzippedPath.pathString,
                withIntermediateDirectories: true
            )
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
            Logger.current.info("Unzipped test products to \(bundlePath.pathString)")

            let xctestrunPath = outputPath.appending(component: "\(scheme).xctestrun")
            try await downloadFile(from: assignment.xctestrunDownloadURL, to: xctestrunPath)
            Logger.current.info("Downloaded filtered .xctestrun file.")

            let targetXctestrunPath = bundlePath.appending(component: "\(scheme).xctestrun")
            try? FileManager.default.removeItem(atPath: targetXctestrunPath.pathString)
            try FileManager.default.copyItem(
                atPath: xctestrunPath.pathString,
                toPath: targetXctestrunPath.pathString
            )

            let selectiveTestingGraphPath = bundlePath.appending(component: SelectiveTestingGraph.fileName)
            var selectiveTestingGraph: SelectiveTestingGraph?
            if let data = try? Data(contentsOf: URL(fileURLWithPath: selectiveTestingGraphPath.pathString)) {
                selectiveTestingGraph = try? JSONDecoder().decode(SelectiveTestingGraph.self, from: data)
                if selectiveTestingGraph != nil {
                    Logger.current.info("Loaded shard hash data from test products bundle.")
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
