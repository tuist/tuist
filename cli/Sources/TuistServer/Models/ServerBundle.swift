import Foundation

public struct ServerBundle: Codable {
    public let id: String
    public let name: String
    public let appBundleId: String
    public let version: String
    public let supportedPlatforms: [String]
    public let installSize: Int
    public let downloadSize: Int?
    public let gitBranch: String?
    public let gitCommitSha: String?
    public let gitRef: String?
    public let insertedAt: Date
    public let uploadedByAccount: String
    public let artifacts: [ServerBundleArtifact]
    public let url: String

    init(
        id: String,
        name: String,
        appBundleId: String,
        version: String,
        supportedPlatforms: [String],
        installSize: Int,
        downloadSize: Int?,
        gitBranch: String?,
        gitCommitSha: String?,
        gitRef: String?,
        insertedAt: Date,
        updatedAt _: Date,
        uploadedByAccount: String,
        artifacts: [ServerBundleArtifact],
        url: String
    ) {
        self.id = id
        self.name = name
        self.appBundleId = appBundleId
        self.version = version
        self.supportedPlatforms = supportedPlatforms
        self.installSize = installSize
        self.downloadSize = downloadSize
        self.gitBranch = gitBranch
        self.gitCommitSha = gitCommitSha
        self.gitRef = gitRef
        self.insertedAt = insertedAt
        self.uploadedByAccount = uploadedByAccount
        self.artifacts = artifacts
        self.url = url
    }

    init?(_ bundle: Components.Schemas.Bundle) {
        id = bundle.id
        name = bundle.name
        appBundleId = bundle.app_bundle_id
        version = bundle.version
        supportedPlatforms = bundle.supported_platforms.map(\.rawValue)
        installSize = bundle.install_size
        downloadSize = bundle.download_size
        gitBranch = bundle.git_branch
        gitCommitSha = bundle.git_commit_sha
        gitRef = bundle.git_ref
        insertedAt = bundle.inserted_at
        uploadedByAccount = bundle.uploaded_by_account
        artifacts = bundle.artifacts?.compactMap { ServerBundleArtifact($0) } ?? []
        url = bundle.url
    }
}

public struct ServerBundleArtifact: Codable {
    public let artifactType: String
    public let path: String
    public let size: Int
    public let shasum: String
    public let children: [ServerBundleArtifact]

    init(
        artifactType: String,
        path: String,
        size: Int,
        shasum: String,
        children: [ServerBundleArtifact]
    ) {
        self.artifactType = artifactType
        self.path = path
        self.size = size
        self.shasum = shasum
        self.children = children
    }

    init?(_ artifact: Components.Schemas.BundleArtifact) {
        artifactType = artifact.artifact_type.rawValue
        path = artifact.path
        size = artifact.size
        shasum = artifact.shasum
        children = artifact.children?.compactMap { ServerBundleArtifact($0) } ?? []
    }
}

#if DEBUG
    extension ServerBundle {
        public static func test(
            id: String = "test-bundle-id",
            name: String = "TestBundle",
            appBundleId: String = "com.example.TestApp",
            version: String = "1.0.0",
            supportedPlatforms: [String] = ["ios"],
            installSize: Int = 1_024_000,
            downloadSize: Int = 512_000,
            gitBranch: String? = "main",
            gitCommitSha: String? = "abc123",
            gitRef: String? = "refs/heads/main",
            insertedAt: Date = Date(),
            updatedAt: Date = Date(),
            uploadedByAccount: String = "test-account",
            artifacts: [ServerBundleArtifact] = [],
            url: String = "https://tuist.dev/test-account/test-project/bundles/test-bundle-id"
        ) -> ServerBundle {
            ServerBundle(
                id: id,
                name: name,
                appBundleId: appBundleId,
                version: version,
                supportedPlatforms: supportedPlatforms,
                installSize: installSize,
                downloadSize: downloadSize,
                gitBranch: gitBranch,
                gitCommitSha: gitCommitSha,
                gitRef: gitRef,
                insertedAt: insertedAt,
                updatedAt: updatedAt,
                uploadedByAccount: uploadedByAccount,
                artifacts: artifacts,
                url: url
            )
        }
    }

    extension ServerBundleArtifact {
        public static func test(
            artifactType: String = "file",
            path: String = "/test/path",
            size: Int = 1024,
            shasum: String = "abc123",
            children: [ServerBundleArtifact] = []
        ) -> ServerBundleArtifact {
            ServerBundleArtifact(
                artifactType: artifactType,
                path: path,
                size: size,
                shasum: shasum,
                children: children
            )
        }
    }
#endif
