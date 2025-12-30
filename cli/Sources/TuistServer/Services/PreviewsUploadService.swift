#if canImport(TuistCore)
    import Command
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

    public enum PreviewsUploadServiceError: LocalizedError, Equatable {
        case appBundleNotFound(AbsolutePath)
        case binaryIdNotFound(AbsolutePath)

        public var errorDescription: String? {
            switch self {
            case let .appBundleNotFound(path):
                return "Could not find app bundle in IPA at \(path.pathString)"
            case let .binaryIdNotFound(path):
                return "Could not extract binary ID from \(path.pathString)"
            }
        }
    }

    @Mockable
    public protocol PreviewsUploadServicing {
        func uploadPreview(
            _ previewUploadType: PreviewUploadType,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            track: String?,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> ServerPreview
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
        private let commandRunner: CommandRunning
        private let precompiledMetadataProvider: PrecompiledMetadataProviding

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
                gitController: GitController(),
                commandRunner: CommandRunner(),
                precompiledMetadataProvider: PrecompiledMetadataProvider()
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
            gitController: GitControlling,
            commandRunner: CommandRunning,
            precompiledMetadataProvider: PrecompiledMetadataProviding
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
            self.commandRunner = commandRunner
            self.precompiledMetadataProvider = precompiledMetadataProvider
        }

        public func uploadPreview(
            _ previewUploadType: PreviewUploadType,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            track: String?,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> ServerPreview {
            let gitInfo = try gitController.gitInfo(workingDirectory: path)

            switch previewUploadType {
            case let .ipa(bundle):
                let binaryId = try await ipaBinaryId(at: bundle.path)
                let preview = try await uploadPreview(
                    buildPath: bundle.path,
                    previewType: .ipa,
                    displayName: bundle.infoPlist.name,
                    version: bundle.infoPlist.version,
                    buildVersion: bundle.infoPlist.buildVersion,
                    bundleIdentifier: bundle.infoPlist.bundleId,
                    icon: iconPaths(for: previewUploadType).first,
                    supportedPlatforms: bundle.infoPlist.supportedPlatforms,
                    gitInfo: gitInfo,
                    binaryId: binaryId,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    track: track,
                    updateProgress: updateProgress
                )
                return preview

            case let .appBundles(bundles):
                var preview: ServerPreview!

                for (index, bundle) in bundles.enumerated() {
                    let progressOffset = Double(index) / Double(bundles.count)
                    let progressScale = 1.0 / Double(bundles.count)
                    let bundleArchivePath = try await fileArchiver
                        .makeFileArchiver(for: [bundle.path])
                        .zip(name: bundle.path.basename)
                    let binaryId = try appBundleBinaryId(at: bundle.path, name: bundle.infoPlist.name)

                    preview = try await uploadPreview(
                        buildPath: bundleArchivePath,
                        previewType: .appBundle,
                        displayName: bundle.infoPlist.name,
                        version: bundle.infoPlist.version,
                        buildVersion: bundle.infoPlist.buildVersion,
                        bundleIdentifier: bundle.infoPlist.bundleId,
                        icon: iconPaths(for: bundle).first,
                        supportedPlatforms: bundle.infoPlist.supportedPlatforms,
                        gitInfo: gitInfo,
                        binaryId: binaryId,
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        track: track,
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
            buildVersion: String,
            bundleIdentifier: String?,
            icon: AbsolutePath?,
            supportedPlatforms: [DestinationType],
            gitInfo: GitInfo,
            binaryId: String,
            fullHandle: String,
            serverURL: URL,
            track: String?,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> ServerPreview {
            updateProgress(0.1)

            let preview = try await retryProvider.runWithRetries {
                let previewUpload =
                    try await multipartUploadStartPreviewsService.startPreviewsMultipartUpload(
                        type: previewType,
                        displayName: displayName,
                        version: version,
                        buildVersion: buildVersion,
                        bundleIdentifier: bundleIdentifier,
                        supportedPlatforms: supportedPlatforms,
                        gitBranch: gitInfo.branch,
                        gitCommitSHA: gitInfo.sha,
                        gitRef: gitInfo.ref,
                        binaryId: binaryId,
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        track: track
                    )

                updateProgress(0.2)

                let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                    artifactPath: buildPath,
                    generateUploadURL: { part in
                        try await multipartUploadGenerateURLPreviewsService.uploadPreview(
                            previewUpload.appBuildId,
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
                    previewUpload.appBuildId,
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
                    .concurrentMap { icon in
                        let outputPath = appPath.appending(component: icon.basenameWithoutExt + "-reverted.png")
                        try await revertiPhoneOptimizations(of: icon, to: outputPath)
                        return outputPath
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

        private func revertiPhoneOptimizations(
            of image: AbsolutePath,
            to outputPath: AbsolutePath
        ) async throws {
            try await commandRunner
                .run(arguments: [
                    "/usr/bin/xcrun",
                    "pngcrush",
                    "-revert-iphone-optimizations",
                    image.pathString,
                    outputPath.pathString,
                ])
                .awaitCompletion()
        }

        private func ipaBinaryId(at path: AbsolutePath) async throws -> String {
            let unarchiver = try fileArchiver.makeFileUnarchiver(for: path)
            let unzippedPath = try unarchiver.unzip()

            guard let appPath = try await fileSystem.glob(directory: unzippedPath, include: ["Payload/*.app"])
                .collect()
                .first
            else {
                throw PreviewsUploadServiceError.appBundleNotFound(path)
            }

            let appName = appPath.basenameWithoutExt
            return try appBundleBinaryId(at: appPath, name: appName)
        }

        private func appBundleBinaryId(at path: AbsolutePath, name: String) throws -> String {
            let executablePath = path.appending(component: name)
            guard let uuids = try? precompiledMetadataProvider.uuids(binaryPath: executablePath),
                  let uuid = uuids.first
            else {
                throw PreviewsUploadServiceError.binaryIdNotFound(executablePath)
            }
            return uuid.uuidString
        }
    }
#endif
