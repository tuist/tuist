import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol AnalyticsArtifactUploadServicing {
    func uploadResultBundle(
        _ resultBundle: AbsolutePath,
        targetHashes: [GraphTarget: String],
        graphPath: AbsolutePath,
        commandEventId: Int,
        serverURL: URL
    ) async throws
}

public final class AnalyticsArtifactUploadService: AnalyticsArtifactUploadServicing {
    private let fileHandler: FileHandling
    private let xcresultToolController: XCResultToolControlling
    private let fileArchiver: FileArchivingFactorying
    private let retryProvider: RetryProviding
    private let multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing
    private let multipartUploadGenerateURLAnalyticsService: MultipartUploadGenerateURLAnalyticsServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing
    private let multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing
    private let completeAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared,
            xcresultToolController: XCResultToolController(),
            fileArchiver: FileArchivingFactory(),
            retryProvider: RetryProvider(),
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
        fileHandler: FileHandling,
        xcresultToolController: XCResultToolControlling,
        fileArchiver: FileArchivingFactorying,
        retryProvider: RetryProviding,
        multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing,
        multipartUploadGenerateURLAnalyticsService: MultipartUploadGenerateURLAnalyticsServicing,
        multipartUploadArtifactService: MultipartUploadArtifactServicing,
        multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing,
        completeAnalyticsArtifactsUploadsService: CompleteAnalyticsArtifactsUploadsServicing
    ) {
        self.fileHandler = fileHandler
        self.xcresultToolController = xcresultToolController
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartAnalyticsService = multipartUploadStartAnalyticsService
        self.multipartUploadGenerateURLAnalyticsService = multipartUploadGenerateURLAnalyticsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompleteAnalyticsService = multipartUploadCompleteAnalyticsService
        self.completeAnalyticsArtifactsUploadsService = completeAnalyticsArtifactsUploadsService
    }

    public func uploadResultBundle(
        _ resultBundle: AbsolutePath,
        targetHashes: [GraphTarget: String],
        graphPath: AbsolutePath,
        commandEventId: Int,
        serverURL: URL
    ) async throws {
        try await uploadAnalyticsArtifact(
            ServerCommandEvent.Artifact(
                type: .resultBundle
            ),
            artifactPath: resultBundle,
            commandEventId: commandEventId,
            serverURL: serverURL
        )

        let invocationRecordString = try xcresultToolController.resultBundleObject(resultBundle)
        let invocationRecordPath = resultBundle.parentDirectory.appending(component: "invocation_record.json")
        try fileHandler.write(invocationRecordString, path: invocationRecordPath, atomically: true)

        let decoder = JSONDecoder()
        let invocationRecord = try decoder.decode(InvocationRecord.self, from: invocationRecordString.data(using: .utf8)!)
        for testActionRecord in invocationRecord.actions._values
            .filter({ $0.schemeCommandName._value == "Test" })
        {
            guard let id = testActionRecord.actionResult.testsRef?.id._value else { continue }
            let resultBundleObjectString = try xcresultToolController.resultBundleObject(
                resultBundle,
                id: id
            )
            let filename = "\(id).json"
            let resultBundleObjectPath = resultBundle.parentDirectory.appending(component: filename)
            try fileHandler.write(resultBundleObjectString, path: resultBundleObjectPath, atomically: true)
            try await uploadAnalyticsArtifact(
                ServerCommandEvent.Artifact(
                    type: .resultBundleObject,
                    name: id
                ),
                artifactPath: resultBundleObjectPath,
                commandEventId: commandEventId,
                serverURL: serverURL
            )
        }

        try await uploadAnalyticsArtifact(
            ServerCommandEvent.Artifact(
                type: .invocationRecord
            ),
            artifactPath: invocationRecordPath,
            commandEventId: commandEventId,
            serverURL: serverURL
        )

        let modules = targetHashes.map { key, value in
            ServerModule(
                hash: value,
                projectRelativePath:
                key.project.xcodeProjPath.relative(to: graphPath),
                name: key.target.name
            )
        }

        try await completeAnalyticsArtifactsUploadsService.completeAnalyticsArtifactsUploads(
            modules: modules,
            commandEventId: commandEventId,
            serverURL: serverURL
        )
    }

    private func uploadAnalyticsArtifact(
        _ artifact: ServerCommandEvent.Artifact,
        artifactPath: AbsolutePath,
        name: String? = nil,
        commandEventId: Int,
        serverURL: URL
    ) async throws {
        let passedArtifactPath = artifactPath
        let artifactPath: AbsolutePath

        switch artifact.type {
        case .resultBundle:
            artifactPath = try fileArchiver.makeFileArchiver(for: [passedArtifactPath])
                .zip(name: passedArtifactPath.basenameWithoutExt)
        case .invocationRecord, .resultBundleObject:
            artifactPath = passedArtifactPath
        }

        try await retryProvider.runWithRetries { [self] in
            let uploadId = try await multipartUploadStartAnalyticsService.uploadAnalyticsArtifact(
                artifact,
                commandEventId: commandEventId,
                serverURL: serverURL
            )

            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: artifactPath,
                generateUploadURL: { partNumber in
                    try await self.multipartUploadGenerateURLAnalyticsService.uploadAnalytics(
                        artifact,
                        commandEventId: commandEventId,
                        partNumber: partNumber,
                        uploadId: uploadId,
                        serverURL: serverURL
                    )
                }
            )

            try await multipartUploadCompleteAnalyticsService.uploadAnalyticsArtifact(
                artifact,
                commandEventId: commandEventId,
                uploadId: uploadId,
                parts: parts,
                serverURL: serverURL
            )
        }
    }
}
