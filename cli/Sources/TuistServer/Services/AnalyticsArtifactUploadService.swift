#if canImport(TuistCore)
    import FileSystem
    import Foundation
    import Mockable
    import Path
    import TuistCore
    import TuistHTTP
    import TuistSupport

    @Mockable
    public protocol AnalyticsArtifactUploadServicing {
        func uploadAndAnalyzeResultBundle(
            _ resultBundle: AbsolutePath,
            accountHandle: String,
            projectHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws

        func uploadResultBundle(
            _ resultBundle: AbsolutePath,
            fullHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws

        func uploadSession(
            _ sessionDirectory: AbsolutePath,
            accountHandle: String,
            projectHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws
    }

    public struct AnalyticsArtifactUploadService: AnalyticsArtifactUploadServicing {
        private let fileSystem: FileSysteming
        private let xcresultToolController: XCResultToolControlling
        private let fileArchiver: FileArchivingFactorying
        private let retryProvider: RetryProviding
        private let fullHandleService: FullHandleServicing
        private let multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing
        private let multipartUploadGenerateURLAnalyticsService:
            MultipartUploadGenerateURLAnalyticsServicing
        private let multipartUploadArtifactService: MultipartUploadArtifactServicing
        private let multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing
        private let completeAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing

        public init() {
            self.init(
                fileSystem: FileSystem(),
                xcresultToolController: XCResultToolController(),
                fileArchiver: FileArchivingFactory(),
                retryProvider: RetryProvider(),
                fullHandleService: FullHandleService(),
                multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsService(),
                multipartUploadGenerateURLAnalyticsService:
                MultipartUploadGenerateURLAnalyticsService(),
                multipartUploadArtifactService: MultipartUploadArtifactService(),
                multipartUploadCompleteAnalyticsService:
                MultipartUploadCompleteAnalyticsService(),
                completeAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsService()
            )
        }

        init(
            fileSystem: FileSysteming,
            xcresultToolController: XCResultToolControlling,
            fileArchiver: FileArchivingFactorying,
            retryProvider: RetryProviding,
            fullHandleService: FullHandleServicing,
            multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing,
            multipartUploadGenerateURLAnalyticsService: MultipartUploadGenerateURLAnalyticsServicing,
            multipartUploadArtifactService: MultipartUploadArtifactServicing,
            multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing,
            completeAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing
        ) {
            self.fileSystem = fileSystem
            self.xcresultToolController = xcresultToolController
            self.fileArchiver = fileArchiver
            self.retryProvider = retryProvider
            self.fullHandleService = fullHandleService
            self.multipartUploadStartAnalyticsService = multipartUploadStartAnalyticsService
            self.multipartUploadGenerateURLAnalyticsService = multipartUploadGenerateURLAnalyticsService
            self.multipartUploadArtifactService = multipartUploadArtifactService
            self.multipartUploadCompleteAnalyticsService = multipartUploadCompleteAnalyticsService
            self.completeAnalyticsArtifactsUploadsService = completeAnalyticsArtifactsUploadsService
        }

        public func uploadAndAnalyzeResultBundle(
            _ resultBundle: AbsolutePath,
            accountHandle: String,
            projectHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws {
            try await uploadAnalyticsArtifact(
                ServerCommandEvent.Artifact(
                    type: .resultBundle
                ),
                artifactPath: resultBundle,
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                commandEventId: commandEventId,
                serverURL: serverURL
            )

            try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryPath in
                let invocationRecordString = try await xcresultToolController.resultBundleObject(
                    resultBundle
                )
                let invocationRecordPath = temporaryPath.appending(component: "invocation_record.json")
                try await fileSystem.writeText(invocationRecordString, at: invocationRecordPath)

                let decoder = JSONDecoder()
                let invocationRecord = try decoder.decode(
                    InvocationRecord.self, from: invocationRecordString.data(using: .utf8)!
                )
                for testActionRecord in invocationRecord.actions._values
                    .filter({ $0.schemeCommandName._value == "Test" })
                {
                    guard let id = testActionRecord.actionResult.testsRef?.id._value else { continue }
                    let resultBundleObjectString = try await xcresultToolController.resultBundleObject(
                        resultBundle,
                        id: id
                    )
                    let filename = "\(id).json"
                    let resultBundleObjectPath = temporaryPath.appending(component: filename)
                    try await fileSystem.writeText(resultBundleObjectString, at: resultBundleObjectPath)
                    try await uploadAnalyticsArtifact(
                        ServerCommandEvent.Artifact(
                            type: .resultBundleObject,
                            name: id
                        ),
                        artifactPath: resultBundleObjectPath,
                        accountHandle: accountHandle,
                        projectHandle: projectHandle,
                        commandEventId: commandEventId,
                        serverURL: serverURL
                    )
                }

                try await uploadAnalyticsArtifact(
                    ServerCommandEvent.Artifact(
                        type: .invocationRecord
                    ),
                    artifactPath: invocationRecordPath,
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    commandEventId: commandEventId,
                    serverURL: serverURL
                )

                try await completeAnalyticsArtifactsUploadsService.completeAnalyticsArtifactsUploads(
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    commandEventId: commandEventId,
                    serverURL: serverURL
                )
            }
        }

        public func uploadResultBundle(
            _ resultBundle: AbsolutePath,
            fullHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws {
            let handles = try fullHandleService.parse(fullHandle)
            try await uploadAnalyticsArtifact(
                ServerCommandEvent.Artifact(
                    type: .resultBundle
                ),
                artifactPath: resultBundle,
                accountHandle: handles.accountHandle,
                projectHandle: handles.projectHandle,
                commandEventId: commandEventId,
                serverURL: serverURL
            )
        }

        public func uploadSession(
            _ sessionDirectory: AbsolutePath,
            accountHandle: String,
            projectHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws {
            try await uploadAnalyticsArtifact(
                ServerCommandEvent.Artifact(
                    type: .session
                ),
                artifactPath: sessionDirectory,
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                commandEventId: commandEventId,
                serverURL: serverURL
            )
        }

        private func uploadAnalyticsArtifact(
            _ artifact: ServerCommandEvent.Artifact,
            artifactPath: AbsolutePath,
            name _: String? = nil,
            accountHandle: String,
            projectHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws {
            let passedArtifactPath = artifactPath
            let artifactPath: AbsolutePath

            switch artifact.type {
            case .resultBundle:
                artifactPath = try await fileArchiver.makeFileArchiver(for: [passedArtifactPath])
                    .zip(name: passedArtifactPath.basenameWithoutExt)
            case .session:
                artifactPath = try await fileArchiver.makeFileArchiver(for: [passedArtifactPath])
                    .zip(name: "session")
            case .invocationRecord, .resultBundleObject:
                artifactPath = passedArtifactPath
            }

            try await retryProvider.runWithRetries { [self] in
                let uploadId = try await multipartUploadStartAnalyticsService.uploadAnalyticsArtifact(
                    artifact,
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    commandEventId: commandEventId,
                    serverURL: serverURL
                )

                let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                    artifactPath: artifactPath,
                    generateUploadURL: { part in
                        try await multipartUploadGenerateURLAnalyticsService.uploadAnalytics(
                            artifact,
                            accountHandle: accountHandle,
                            projectHandle: projectHandle,
                            commandEventId: commandEventId,
                            partNumber: part.number,
                            uploadId: uploadId,
                            serverURL: serverURL,
                            contentLength: part.contentLength
                        )
                    },
                    updateProgress: { _ in }
                )

                try await multipartUploadCompleteAnalyticsService.uploadAnalyticsArtifact(
                    artifact,
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    commandEventId: commandEventId,
                    uploadId: uploadId,
                    parts: parts,
                    serverURL: serverURL
                )
            }
        }
    }
#endif
