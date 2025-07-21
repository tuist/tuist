import Foundation

public struct ServerBundle: Codable {
    public let id: String
    public let name: String
    public let appBundleId: String
    public let version: String
    public let supportedPlatforms: [String]
    public let installSize: Int
    public let downloadSize: Int
    public let gitBranch: String?
    public let gitCommitSha: String?
    public let gitRef: String?
    public let insertedAt: Date
    public let updatedAt: Date
    public let uploadedByAccount: String
    public let artifacts: [ServerBundleArtifact]

    init(
        id: String,
        name: String,
        appBundleId: String,
        version: String,
        supportedPlatforms: [String],
        installSize: Int,
        downloadSize: Int,
        gitBranch: String?,
        gitCommitSha: String?,
        gitRef: String?,
        insertedAt: Date,
        updatedAt: Date,
        uploadedByAccount: String,
        artifacts: [ServerBundleArtifact]
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
        self.updatedAt = updatedAt
        self.uploadedByAccount = uploadedByAccount
        self.artifacts = artifacts
    }

    init?(_ bundle: Components.Schemas.Bundle) {        
        self.id = bundle.id
        self.name = bundle.name
        self.appBundleId = bundle.app_bundle_id
        self.version = bundle.version
        self.supportedPlatforms = bundle.supported_platforms
        self.installSize = bundle.install_size
        self.downloadSize = bundle.download_size
        self.gitBranch = bundle.git_branch
        self.gitCommitSha = bundle.git_commit_sha
        self.gitRef = bundle.git_ref
        self.insertedAt = bundle.inserted_at
        self.updatedAt = bundle.updated_at
        self.uploadedByAccount = bundle.uploaded_by_account
        self.artifacts = bundle.artifacts.compactMap { ServerBundleArtifact($0) }
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
        self.artifactType = artifact.artifact_type.rawValue
        self.path = artifact.path
        self.size = artifact.size
        self.shasum = artifact.shasum
        self.children = artifact.children?.compactMap { ServerBundleArtifact($0) } ?? []
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
            installSize: Int = 1024000,
            downloadSize: Int = 512000,
            gitBranch: String? = "main",
            gitCommitSha: String? = "abc123",
            gitRef: String? = "refs/heads/main",
            insertedAt: Date = Date(),
            updatedAt: Date = Date(),
            uploadedByAccount: String = "test-account",
            artifacts: [ServerBundleArtifact] = []
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
                artifacts: artifacts
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
