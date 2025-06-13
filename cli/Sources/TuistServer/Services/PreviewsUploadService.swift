#if canImport(TuistCore)
    import FileSystem
    import Foundation
    import Mockable
    import Path
    import TuistAutomation
    import TuistCore
    import TuistGit
    import TuistSimulator
    import TuistSupport

    public enum PreviewUploadType: Equatable {
        case ipa(AppBundle)
        case appBundles([AppBundle])
    }

    @Mockable
    public protocol PreviewsUploadServicing {
        func uploadPreview(
            _ previewUploadType: PreviewUploadType,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> Preview
    }

    public struct PreviewsUploadService: PreviewsUploadServicing {
        private let fileSystem: FileSysteming
        private let fileArchiver: FileArchivingFactorying
        private let retryProvider: RetryProviding
        private let multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing
        private let multipartUploadGenerateURLPreviewsService:
            MultipartUploadGenerateURLPreviewsServicing
        private let multipartUploadArtifactService: MultipartUploadArtifactServicing
        private let multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing
        private let uploadPreviewIconService: UploadPreviewIconServicing
        private let gitController: GitControlling

        public init() {
            self.init(
                fileSystem: FileSystem(),
                fileArchiver: FileArchivingFactory(),
                retryProvider: RetryProvider(),
                multipartUploadStartPreviewsService: MultipartUploadStartPreviewsService(),
                multipartUploadGenerateURLPreviewsService:
                MultipartUploadGenerateURLPreviewsService(),
                multipartUploadArtifactService: MultipartUploadArtifactService(),
                multipartUploadCompletePreviewsService:
                MultipartUploadCompletePreviewsService(),
                uploadPreviewIconService: UploadPreviewIconService(),
                gitController: GitController()
            )
        }

        init(
            fileSystem: FileSysteming,
            fileArchiver: FileArchivingFactorying,
            retryProvider: RetryProviding,
            multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing,
            multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing,
            multipartUploadArtifactService: MultipartUploadArtifactServicing,
            multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing,
            uploadPreviewIconService: UploadPreviewIconServicing,
            gitController: GitControlling
        ) {
            self.fileSystem = fileSystem
            self.fileArchiver = fileArchiver
            self.retryProvider = retryProvider
            self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
            self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
            self.multipartUploadArtifactService = multipartUploadArtifactService
            self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
            self.uploadPreviewIconService = uploadPreviewIconService
            self.gitController = gitController
        }

        public func uploadPreview(
            _ previewUploadType: PreviewUploadType,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> Preview {
            let gitInfo = try gitController.gitInfo(workingDirectory: path)
            let gitCommitSHA = gitInfo.sha
            let gitBranch = gitInfo.branch

            switch previewUploadType {
            case let .ipa(bundle):
                let preview = try await uploadPreview(
                    buildPath: bundle.path,
                    previewType: .ipa,
                    displayName: bundle.infoPlist.name,
                    version: bundle.infoPlist.version,
                    bundleIdentifier: bundle.infoPlist.bundleId,
                    icon: iconPaths(for: previewUploadType).first,
                    supportedPlatforms: bundle.infoPlist.supportedPlatforms,
                    gitBranch: gitBranch,
                    gitCommitSHA: gitCommitSHA,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    updateProgress: updateProgress
                )
                return preview

            case let .appBundles(bundles):
                var preview: Preview!

                for (index, bundle) in bundles.enumerated() {
                    let progressOffset = Double(index) / Double(bundles.count)
                    let progressScale = 1.0 / Double(bundles.count)
                    let bundleArchivePath = try await fileArchiver
                        .makeFileArchiver(for: [bundle.path])
                        .zip(name: bundle.path.basename)

                    preview = try await uploadPreview(
                        buildPath: bundleArchivePath,
                        previewType: .appBundle,
                        displayName: bundle.infoPlist.name,
                        version: bundle.infoPlist.version,
                        bundleIdentifier: bundle.infoPlist.bundleId,
                        icon: iconPaths(for: bundle).first,
                        supportedPlatforms: bundle.infoPlist.supportedPlatforms,
                        gitBranch: gitBranch,
                        gitCommitSHA: gitCommitSHA,
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        updateProgress: { progress in
                            updateProgress(progressOffset + progress * progressScale)
                        }
                    )
                }

                return preview
            }
        }

        private func uploadPreview(
            buildPath: AbsolutePath,
            previewType: PreviewType,
            displayName: String,
            version: String?,
            bundleIdentifier: String?,
            icon: AbsolutePath?,
            supportedPlatforms: [DestinationType],
            gitBranch: String?,
            gitCommitSHA: String?,
            fullHandle: String,
            serverURL: URL,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> Preview {
            updateProgress(0.1)

            let preview = try await retryProvider.runWithRetries {
                let previewUpload =
                    try await multipartUploadStartPreviewsService.startPreviewsMultipartUpload(
                        type: previewType,
                        displayName: displayName,
                        version: version,
                        bundleIdentifier: bundleIdentifier,
                        supportedPlatforms: supportedPlatforms,
                        gitBranch: gitBranch,
                        gitCommitSHA: gitCommitSHA,
                        fullHandle: fullHandle,
                        serverURL: serverURL
                    )

                updateProgress(0.2)

                let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                    artifactPath: buildPath,
                    generateUploadURL: { part in
                        try await multipartUploadGenerateURLPreviewsService.uploadPreview(
                            previewUpload.previewId,
                            partNumber: part.number,
                            uploadId: previewUpload.uploadId,
                            fullHandle: fullHandle,
                            serverURL: serverURL,
                            contentLength: part.contentLength
                        )
                    },
                    updateProgress: {
                        updateProgress(0.2 + $0 * 0.7)
                    }
                )

                return try await multipartUploadCompletePreviewsService.completePreviewUpload(
                    previewUpload.previewId,
                    uploadId: previewUpload.uploadId,
                    parts: parts,
                    fullHandle: fullHandle,
                    serverURL: serverURL
                )
            }

            if let icon {
                try await uploadPreviewIconService.uploadPreviewIcon(
                    icon,
                    preview: preview,
                    serverURL: serverURL,
                    fullHandle: fullHandle
                )
            }

            return preview
        }

        private func iconPaths(for previewUploadType: PreviewUploadType) async throws -> [AbsolutePath] {
            switch previewUploadType {
            case let .appBundles(appBundles):
                return try await appBundles.concurrentMap { try await iconPaths(for: $0) }.flatMap { $0 }
            case let .ipa(appBundle):
                let unarchiver = try fileArchiver.makeFileUnarchiver(for: appBundle.path)
                guard let appPath = try await fileSystem.glob(directory: unarchiver.unzip(), include: ["*.app", "Payload/*.app"])
                    .collect()
                    .first
                else {
                    return []
                }

                return try await (appBundle.infoPlist.bundleIcons?.primaryIcon?.iconFiles ?? [])
                    // This is a convention for iOS icons. We might need to adjust this for other platforms in the future.
                    .map { appPath.appending(component: $0 + "@2x.png") }
                    .concurrentFilter {
                        try await fileSystem.exists($0)
                    }
            }
        }

        private func iconPaths(for appBundle: AppBundle) async throws -> [AbsolutePath] {
            try await (appBundle.infoPlist.bundleIcons?.primaryIcon?.iconFiles ?? [])
                // This is a convention for iOS icons. We might need to adjust this for other platforms in the future.
                .map { appBundle.path.appending(component: $0 + "@2x.png") }
                .concurrentFilter {
                    try await fileSystem.exists($0)
                }
        }
    }
#endif
