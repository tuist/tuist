import CryptoKit
import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment

public struct APKMetadata: Equatable, Sendable {
    public let packageName: String
    public let versionName: String
    public let versionCode: String
    public let displayName: String

    public init(packageName: String, versionName: String, versionCode: String, displayName: String) {
        self.packageName = packageName
        self.versionName = versionName
        self.versionCode = versionCode
        self.displayName = displayName
    }
}

// MARK: - Cross-platform APK Preview Upload

@Mockable
public protocol APKPreviewUploadServicing {
    func uploadAPKPreview(
        apkPath: AbsolutePath,
        metadata: APKMetadata,
        gitCommitSHA: String?,
        gitBranch: String?,
        gitRef: String?,
        fullHandle: String,
        serverURL: URL,
        track: String?,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> PreviewUploadResult
}

#if canImport(TuistSupport)
    import TuistSupport

public struct APKPreviewUploadService: APKPreviewUploadServicing {
    private let fileSystem: FileSysteming
    private let fileArchiver: FileArchivingFactorying
    private let retryProvider: RetryProviding
    private let multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing
    private let multipartUploadGenerateURLPreviewsService:
        MultipartUploadGenerateURLPreviewsServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing
    private let multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing

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
            MultipartUploadCompletePreviewsService()
        )
    }

    init(
        fileSystem: FileSysteming,
        fileArchiver: FileArchivingFactorying,
        retryProvider: RetryProviding,
        multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing,
        multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing,
        multipartUploadArtifactService: MultipartUploadArtifactServicing,
        multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing
    ) {
        self.fileSystem = fileSystem
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
        self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
    }

    public func uploadAPKPreview(
        apkPath: AbsolutePath,
        metadata: APKMetadata,
        gitCommitSHA: String?,
        gitBranch: String?,
        gitRef: String?,
        fullHandle: String,
        serverURL: URL,
        track: String?,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> PreviewUploadResult {
        let bundleArchivePath = try await fileArchiver
            .makeFileArchiver(for: [apkPath])
            .zip(name: apkPath.basename)
        let buildVersion = resolvedBuildVersion(metadata.versionCode)
        let binaryId = try await apkBinaryId(at: apkPath)

        return try await uploadPreview(
            buildPath: bundleArchivePath,
            previewType: .apk,
            displayName: metadata.displayName,
            version: metadata.versionName,
            buildVersion: buildVersion,
            bundleIdentifier: metadata.packageName,
            supportedPlatforms: [.android],
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            binaryId: binaryId,
            fullHandle: fullHandle,
            serverURL: serverURL,
            track: track,
            updateProgress: updateProgress
        )
    }

    private func resolvedBuildVersion(_ buildVersion: String) -> String {
        let variables = Environment.current.variables
        if let override = variables["TUIST_PREVIEW_BUILD_VERSION"], !override.isEmpty {
            return override
        }
        if let suffix = variables["TUIST_PREVIEW_BUILD_VERSION_SUFFIX"], !suffix.isEmpty {
            return "\(buildVersion)-\(suffix)"
        }
        return buildVersion
    }

    private func uploadPreview(
        buildPath: AbsolutePath,
        previewType: PreviewType,
        displayName: String,
        version: String?,
        buildVersion: String,
        bundleIdentifier: String?,
        supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform],
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        binaryId: String,
        fullHandle: String,
        serverURL: URL,
        track: String?,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> PreviewUploadResult {
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
                    gitBranch: gitBranch,
                    gitCommitSHA: gitCommitSHA,
                    gitRef: gitRef,
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

        return preview
    }

    private func apkBinaryId(at path: AbsolutePath) async throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path.pathString))
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
#endif

// MARK: - macOS-only Preview Upload (IPA, App Bundles)

#if canImport(TuistCore)
    import Command
    import TuistAutomation
    import TuistCore
    import TuistGit
    import TuistSimulator

    public enum PreviewUploadType: Equatable {
        case ipa(AppBundle)
        case appBundles([AppBundle])
        case apk(path: AbsolutePath, metadata: APKMetadata)
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
        ) async throws -> PreviewUploadResult
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
        private let apkPreviewUploadService: APKPreviewUploadServicing

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
                precompiledMetadataProvider: PrecompiledMetadataProvider(),
                apkPreviewUploadService: APKPreviewUploadService()
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
            precompiledMetadataProvider: PrecompiledMetadataProviding,
            apkPreviewUploadService: APKPreviewUploadServicing
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
            self.apkPreviewUploadService = apkPreviewUploadService
        }

        public func uploadPreview(
            _ previewUploadType: PreviewUploadType,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            track: String?,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> PreviewUploadResult {
            let gitInfo = try gitController.gitInfo(workingDirectory: path)

            switch previewUploadType {
            case let .ipa(bundle):
                let buildVersion = resolvedBuildVersion(bundle.infoPlist.buildVersion)
                let binaryId = try await ipaBinaryId(at: bundle.path)
                let preview = try await uploadPreview(
                    buildPath: bundle.path,
                    previewType: .ipa,
                    displayName: bundle.infoPlist.name,
                    version: bundle.infoPlist.version,
                    buildVersion: buildVersion,
                    bundleIdentifier: bundle.infoPlist.bundleId,
                    icon: iconPaths(for: previewUploadType).first,
                    supportedPlatforms: bundle.infoPlist.supportedPlatforms
                        .map(Components.Schemas.PreviewSupportedPlatform.init),
                    gitInfo: gitInfo,
                    binaryId: binaryId,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    track: track,
                    updateProgress: updateProgress
                )
                return preview

            case let .appBundles(bundles):
                var preview: PreviewUploadResult!

                for (index, bundle) in bundles.enumerated() {
                    let progressOffset = Double(index) / Double(bundles.count)
                    let progressScale = 1.0 / Double(bundles.count)
                    let bundleArchivePath = try await fileArchiver
                        .makeFileArchiver(for: [bundle.path])
                        .zip(name: bundle.path.basename)
                    let buildVersion = resolvedBuildVersion(bundle.infoPlist.buildVersion)
                    let binaryId = try appBundleBinaryId(at: bundle.path, name: bundle.infoPlist.name)

                    preview = try await uploadPreview(
                        buildPath: bundleArchivePath,
                        previewType: .appBundle,
                        displayName: bundle.infoPlist.name,
                        version: bundle.infoPlist.version,
                        buildVersion: buildVersion,
                        bundleIdentifier: bundle.infoPlist.bundleId,
                        icon: iconPaths(for: bundle).first,
                        supportedPlatforms: bundle.infoPlist.supportedPlatforms
                            .map(Components.Schemas.PreviewSupportedPlatform.init),
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

            case let .apk(apkPath, metadata):
                return try await apkPreviewUploadService.uploadAPKPreview(
                    apkPath: apkPath,
                    metadata: metadata,
                    gitCommitSHA: gitInfo.sha,
                    gitBranch: gitInfo.branch,
                    gitRef: gitInfo.ref,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    track: track,
                    updateProgress: updateProgress
                )
            }
        }

        private func resolvedBuildVersion(_ buildVersion: String) -> String {
            let variables = Environment.current.variables
            if let override = variables["TUIST_PREVIEW_BUILD_VERSION"], !override.isEmpty {
                return override
            }
            if let suffix = variables["TUIST_PREVIEW_BUILD_VERSION_SUFFIX"], !suffix.isEmpty {
                return "\(buildVersion)-\(suffix)"
            }
            return buildVersion
        }

        private func uploadPreview(
            buildPath: AbsolutePath,
            previewType: PreviewType,
            displayName: String,
            version: String?,
            buildVersion: String,
            bundleIdentifier: String?,
            icon: AbsolutePath?,
            supportedPlatforms: [Components.Schemas.PreviewSupportedPlatform],
            gitInfo: GitInfo,
            binaryId: String,
            fullHandle: String,
            serverURL: URL,
            track: String?,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> PreviewUploadResult {
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
                    previewId: preview.id,
                    serverURL: serverURL,
                    fullHandle: fullHandle
                )
            }

            return preview
        }

        private func iconPaths(for previewUploadType: PreviewUploadType) async throws -> [AbsolutePath] {
            switch previewUploadType {
            case .apk:
                return []
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
