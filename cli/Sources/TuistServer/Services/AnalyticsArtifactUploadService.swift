#if canImport(TuistCore)
    import FileSystem
    import Foundation
    import Mockable
    import Path
    import TuistCore
    import TuistHTTP
    import TuistLogging
    import TuistSupport
    #if canImport(TuistAppleArchiver)
        import TuistAppleArchiver
    #endif

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
        private let fullHandleService: FullHandleServicing
        private let multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing
        private let multipartUploadGenerateURLAnalyticsService:
            MultipartUploadGenerateURLAnalyticsServicing
        private let multipartUploadArtifactService: MultipartUploadArtifactServicing
        private let multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing
        private let completeAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing
        #if canImport(TuistAppleArchiver)
            private let appleArchiver: AppleArchiving
        #endif

        public init() {
            self.init(
                fileSystem: FileSystem(),
                xcresultToolController: XCResultToolController(),
                fileArchiver: FileArchivingFactory(),
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
            self.fullHandleService = fullHandleService
            self.multipartUploadStartAnalyticsService = multipartUploadStartAnalyticsService
            self.multipartUploadGenerateURLAnalyticsService = multipartUploadGenerateURLAnalyticsService
            self.multipartUploadArtifactService = multipartUploadArtifactService
            self.multipartUploadCompleteAnalyticsService = multipartUploadCompleteAnalyticsService
            self.completeAnalyticsArtifactsUploadsService = completeAnalyticsArtifactsUploadsService
            #if canImport(TuistAppleArchiver)
                appleArchiver = AppleArchiver()
            #endif
        }

        #if canImport(TuistAppleArchiver)
            init(
                fileSystem: FileSysteming,
                xcresultToolController: XCResultToolControlling,
                fileArchiver: FileArchivingFactorying,
                fullHandleService: FullHandleServicing,
                multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing,
                multipartUploadGenerateURLAnalyticsService: MultipartUploadGenerateURLAnalyticsServicing,
                multipartUploadArtifactService: MultipartUploadArtifactServicing,
                multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing,
                completeAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing,
                appleArchiver: AppleArchiving
            ) {
                self.fileSystem = fileSystem
                self.xcresultToolController = xcresultToolController
                self.fileArchiver = fileArchiver
                self.fullHandleService = fullHandleService
                self.multipartUploadStartAnalyticsService = multipartUploadStartAnalyticsService
                self.multipartUploadGenerateURLAnalyticsService = multipartUploadGenerateURLAnalyticsService
                self.multipartUploadArtifactService = multipartUploadArtifactService
                self.multipartUploadCompleteAnalyticsService = multipartUploadCompleteAnalyticsService
                self.completeAnalyticsArtifactsUploadsService = completeAnalyticsArtifactsUploadsService
                self.appleArchiver = appleArchiver
            }
        #endif

        public func uploadAndAnalyzeResultBundle(
            _ resultBundle: AbsolutePath,
            accountHandle: String,
            projectHandle: String,
            commandEventId: String,
            serverURL: URL
        ) async throws {
            Logger.current.debug("Starting result bundle upload and analyze for \(resultBundle.pathString)")
            let totalStart = Date()

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
                let parseStart = Date()
                let invocationRecordString = try await xcresultToolController.resultBundleObject(
                    resultBundle
                )
                let invocationRecordPath = temporaryPath.appending(component: "invocation_record.json")
                try await fileSystem.writeText(invocationRecordString, at: invocationRecordPath)

                let decoder = JSONDecoder()
                let invocationRecord = try decoder.decode(
                    InvocationRecord.self, from: invocationRecordString.data(using: .utf8)!
                )
                Logger.current.debug(
                    "Parsed invocation record in \(String(format: "%.2fs", Date().timeIntervalSince(parseStart)))"
                )

                for testActionRecord in invocationRecord.actions._values
                    .filter({ $0.schemeCommandName._value == "Test" })
                {
                    guard let id = testActionRecord.actionResult.testsRef?.id._value else { continue }
                    let actionParseStart = Date()
                    let resultBundleObjectString = try await xcresultToolController.resultBundleObject(
                        resultBundle,
                        id: id
                    )
                    let filename = "\(id).json"
                    let resultBundleObjectPath = temporaryPath.appending(component: filename)
                    try await fileSystem.writeText(resultBundleObjectString, at: resultBundleObjectPath)
                    Logger.current.debug(
                        "Parsed result bundle object \(id) in \(String(format: "%.2fs", Date().timeIntervalSince(actionParseStart)))"
                    )
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

            Logger.current.debug(
                "Result bundle upload and analyze finished in \(String(format: "%.2fs", Date().timeIntervalSince(totalStart)))"
            )
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
            let artifactLabel = "\(artifact.type)\(artifact.name.map { " (\($0))" } ?? "")"

            let archiveStart = Date()
            switch artifact.type {
            case .resultBundle:
                #if canImport(TuistAppleArchiver)
                    // AppleArchive (LZFSE) is substantially faster than deflate for xcresult
                    // bundles and skips the pre-copy the zip path needs. The server-side
                    // `xcode_processor` sniffs magic bytes to decide between zip and aar.
                    let archiveDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-analytics-archive")
                    let archivePath = archiveDirectory.appending(
                        component: "\(passedArtifactPath.basenameWithoutExt).aar"
                    )
                    try await appleArchiver.compress(
                        directory: passedArtifactPath,
                        to: archivePath,
                        excludePatterns: []
                    )
                    artifactPath = archivePath
                #else
                    artifactPath = try await fileArchiver.makeFileArchiver(for: [passedArtifactPath])
                        .zip(name: passedArtifactPath.basenameWithoutExt)
                #endif
            case .session:
                artifactPath = try await fileArchiver.makeFileArchiver(for: [passedArtifactPath])
                    .zip(name: "session")
            case .invocationRecord, .resultBundleObject:
                artifactPath = passedArtifactPath
            }
            if artifact.type == .resultBundle || artifact.type == .session {
                let archiveElapsed = Date().timeIntervalSince(archiveStart)
                Logger.current.debug(
                    "Archived \(artifactLabel) in \(String(format: "%.2fs", archiveElapsed))"
                )
            }

            let uploadStart = Date()
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
            let uploadElapsed = Date().timeIntervalSince(uploadStart)
            Logger.current.debug(
                "Uploaded \(artifactLabel) in \(String(format: "%.2fs", uploadElapsed)) (\(parts.count) parts)"
            )
        }
    }
#endif
