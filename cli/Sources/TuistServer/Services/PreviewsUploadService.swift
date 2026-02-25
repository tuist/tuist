import Crypto
import FileSystem
import Foundation
import Mockable
import Path
import TuistAndroid
import TuistEnvironment

#if canImport(TuistCore)
    import Command
    import TuistAutomation
    import TuistCore
    import TuistSimulator
#endif

#if canImport(TuistSupport)
    import TuistSupport
#endif

// MARK: - Types

public enum PreviewUploadType: Equatable {
    case apk(path: AbsolutePath, metadata: APKMetadata)
    #if canImport(TuistCore)
        case ipa(AppBundle)
        case appBundles([AppBundle])
    #endif
}

#if canImport(TuistCore)
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
#endif

// MARK: - Protocol

@Mockable
public protocol PreviewsUploadServicing {
    func uploadPreview(
        _ previewUploadType: PreviewUploadType,
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        track: String?,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> Components.Schemas.Preview
}

// MARK: - Implementation

#if canImport(TuistSupport)
    // swiftlint:disable:next type_body_length
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

        #if canImport(TuistCore)
            private let commandRunner: CommandRunning
            private let precompiledMetadataProvider: PrecompiledMetadataProviding
        #endif

        public init() {
            #if canImport(TuistCore)
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
                    commandRunner: CommandRunner(),
                    precompiledMetadataProvider: PrecompiledMetadataProvider()
                )
            #else
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
                    uploadPreviewIconService: UploadPreviewIconService()
                )
            #endif
        }

        #if canImport(TuistCore)
            init(
                fileSystem: FileSysteming,
                fileArchiver: FileArchivingFactorying,
                retryProvider: RetryProviding,
                multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing,
                multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing,
                multipartUploadArtifactService: MultipartUploadArtifactServicing,
                multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing,
                uploadPreviewIconService: UploadPreviewIconServicing,
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
                self.commandRunner = commandRunner
                self.precompiledMetadataProvider = precompiledMetadataProvider
            }
        #else
            init(
                fileSystem: FileSysteming,
                fileArchiver: FileArchivingFactorying,
                retryProvider: RetryProviding,
                multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing,
                multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing,
                multipartUploadArtifactService: MultipartUploadArtifactServicing,
                multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing,
                uploadPreviewIconService: UploadPreviewIconServicing
            ) {
                self.fileSystem = fileSystem
                self.fileArchiver = fileArchiver
                self.retryProvider = retryProvider
                self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
                self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
                self.multipartUploadArtifactService = multipartUploadArtifactService
                self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
                self.uploadPreviewIconService = uploadPreviewIconService
            }
        #endif

        // swiftlint:disable:next function_body_length
        public func uploadPreview(
            _ previewUploadType: PreviewUploadType,
            fullHandle: String,
            serverURL: URL,
            gitBranch: String?,
            gitCommitSHA: String?,
            gitRef: String?,
            track: String?,
            updateProgress: @escaping (Double) -> Void
        ) async throws -> Components.Schemas.Preview {
            switch previewUploadType {
            case let .apk(apkPath, metadata):
                let buildVersion = resolvedBuildVersion(metadata.versionCode)
                let binaryId = try await apkBinaryId(at: apkPath)

                let preview = try await uploadPreviewBuild(
                    buildPath: apkPath,
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

                if let iconPath = metadata.iconPath {
                    let unarchiver = try fileArchiver.makeFileUnarchiver(for: apkPath)
                    let unzippedPath = try unarchiver.unzip()
                    let iconAbsolutePath = unzippedPath.appending(iconPath)
                    if try await fileSystem.exists(iconAbsolutePath) {
                        try await uploadPreviewIconService.uploadPreviewIcon(
                            iconAbsolutePath,
                            previewId: preview.id,
                            serverURL: serverURL,
                            fullHandle: fullHandle
                        )
                    }
                }

                return preview

            #if canImport(TuistCore)
                case let .ipa(bundle):
                    let buildVersion = resolvedBuildVersion(bundle.infoPlist.buildVersion)
                    let binaryId = try await ipaBinaryId(at: bundle.path)
                    let icon = try await iconPaths(for: previewUploadType).first
                    let preview = try await uploadPreviewBuild(
                        buildPath: bundle.path,
                        previewType: .ipa,
                        displayName: bundle.infoPlist.name,
                        version: bundle.infoPlist.version,
                        buildVersion: buildVersion,
                        bundleIdentifier: bundle.infoPlist.bundleId,
                        supportedPlatforms: bundle.infoPlist.supportedPlatforms
                            .map(Components.Schemas.PreviewSupportedPlatform.init),
                        gitBranch: gitBranch,
                        gitCommitSHA: gitCommitSHA,
                        gitRef: gitRef,
                        binaryId: binaryId,
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        track: track,
                        updateProgress: updateProgress
                    )

                    if let icon {
                        try await uploadPreviewIconService.uploadPreviewIcon(
                            icon,
                            previewId: preview.id,
                            serverURL: serverURL,
                            fullHandle: fullHandle
                        )
                    }

                    return preview

                case let .appBundles(bundles):
                    var preview: Components.Schemas.Preview!

                    for (index, bundle) in bundles.enumerated() {
                        let progressOffset = Double(index) / Double(bundles.count)
                        let progressScale = 1.0 / Double(bundles.count)
                        let bundleArchivePath = try await fileArchiver
                            .makeFileArchiver(for: [bundle.path])
                            .zip(name: bundle.path.basename)
                        let buildVersion = resolvedBuildVersion(bundle.infoPlist.buildVersion)
                        let binaryId = try appBundleBinaryId(at: bundle.path, name: bundle.infoPlist.name)

                        preview = try await uploadPreviewBuild(
                            buildPath: bundleArchivePath,
                            previewType: .appBundle,
                            displayName: bundle.infoPlist.name,
                            version: bundle.infoPlist.version,
                            buildVersion: buildVersion,
                            bundleIdentifier: bundle.infoPlist.bundleId,
                            supportedPlatforms: bundle.infoPlist.supportedPlatforms
                                .map(Components.Schemas.PreviewSupportedPlatform.init),
                            gitBranch: gitBranch,
                            gitCommitSHA: gitCommitSHA,
                            gitRef: gitRef,
                            binaryId: binaryId,
                            fullHandle: fullHandle,
                            serverURL: serverURL,
                            track: track,
                            updateProgress: { progress in
                                updateProgress(progressOffset + progress * progressScale)
                            }
                        )
                    }

                    if let icon = try await iconPaths(for: previewUploadType).first {
                        try await uploadPreviewIconService.uploadPreviewIcon(
                            icon,
                            previewId: preview.id,
                            serverURL: serverURL,
                            fullHandle: fullHandle
                        )
                    }

                    return preview
            #endif
            }
        }

        // MARK: - Shared

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

        private func uploadPreviewBuild(
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
        ) async throws -> Components.Schemas.Preview {
            updateProgress(0.1)

            return try await retryProvider.runWithRetries {
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
        }

        // MARK: - APK (cross-platform)

        private func apkBinaryId(at path: AbsolutePath) async throws -> String {
            let data = try Data(contentsOf: URL(fileURLWithPath: path.pathString))
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        // MARK: - Apple (macOS-only)

        #if canImport(TuistCore)
            private func iconPaths(for previewUploadType: PreviewUploadType) async throws -> [AbsolutePath] {
                switch previewUploadType {
                case .apk:
                    return []
                case let .appBundles(appBundles):
                    return try await appBundles.concurrentMap { try await iconPaths(for: $0) }.flatMap { $0 }
                case let .ipa(appBundle):
                    let unarchiver = try fileArchiver.makeFileUnarchiver(for: appBundle.path)
                    guard let appPath = try await fileSystem.glob(
                        directory: unarchiver.unzip(),
                        include: ["*.app", "Payload/*.app"]
                    )
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
        #endif
    }
#endif
