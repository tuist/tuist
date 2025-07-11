import Foundation

public struct ServerBundle: Codable, Identifiable {
    public let id: String
    public let appBundleId: String?
    public let name: String
    public let installSize: Int
    public let downloadSize: Int?
    public let supportedPlatforms: [String]?
    public let version: String
    public let gitBranch: String?
    public let gitCommitSha: String?
    public let gitRef: String?
    public let insertedAt: Date?
    public let updatedAt: Date?
    public let artifacts: [ServerBundleArtifact]?

    init(
        id: String,
        appBundleId: String?,
        name: String,
        installSize: Int,
        downloadSize: Int?,
        supportedPlatforms: [String]?,
        version: String,
        gitBranch: String?,
        gitCommitSha: String?,
        gitRef: String?,
        insertedAt: Date?,
        updatedAt: Date?,
        artifacts: [ServerBundleArtifact]?
    ) {
        self.id = id
        self.appBundleId = appBundleId
        self.name = name
        self.installSize = installSize
        self.downloadSize = downloadSize
        self.supportedPlatforms = supportedPlatforms
        self.version = version
        self.gitBranch = gitBranch
        self.gitCommitSha = gitCommitSha
        self.gitRef = gitRef
        self.insertedAt = insertedAt
        self.updatedAt = updatedAt
        self.artifacts = artifacts
    }
}

public struct ServerBundleArtifact: Codable, Identifiable {
    public let id: String
    public let artifactType: String?
    public let path: String
    public let size: Int
    public let shasum: String?
    public let children: [ServerBundleArtifact]?

    init(
        id: String,
        artifactType: String?,
        path: String,
        size: Int,
        shasum: String?,
        children: [ServerBundleArtifact]?
    ) {
        self.id = id
        self.artifactType = artifactType
        self.path = path
        self.size = size
        self.shasum = shasum
        self.children = children
    }
}

public struct ServerBundleListResponse: Codable {
    public let bundles: [ServerBundle]
    public let meta: ServerBundleListMeta?

    init(
        bundles: [ServerBundle],
        meta: ServerBundleListMeta?
    ) {
        self.bundles = bundles
        self.meta = meta
    }
}

public struct ServerBundleListMeta: Codable {
    public let totalCount: Int
    public let pageSize: Int
    public let hasNextPage: Bool
    public let hasPreviousPage: Bool

    init(
        totalCount: Int,
        pageSize: Int,
        hasNextPage: Bool,
        hasPreviousPage: Bool
    ) {
        self.totalCount = totalCount
        self.pageSize = pageSize
        self.hasNextPage = hasNextPage
        self.hasPreviousPage = hasPreviousPage
    }
}

#if DEBUG
    extension ServerBundle {
        public static func test(
            id: String = "test-bundle-id",
            appBundleId: String? = "com.test.app",
            name: String = "TestApp",
            installSize: Int = 1024000,
            downloadSize: Int? = 512000,
            supportedPlatforms: [String]? = ["ios"],
            version: String = "1.0.0",
            gitBranch: String? = "main",
            gitCommitSha: String? = "abc123",
            gitRef: String? = "refs/heads/main",
            insertedAt: Date? = Date(),
            updatedAt: Date? = Date(),
            artifacts: [ServerBundleArtifact]? = nil
        ) -> ServerBundle {
            ServerBundle(
                id: id,
                appBundleId: appBundleId,
                name: name,
                installSize: installSize,
                downloadSize: downloadSize,
                supportedPlatforms: supportedPlatforms,
                version: version,
                gitBranch: gitBranch,
                gitCommitSha: gitCommitSha,
                gitRef: gitRef,
                insertedAt: insertedAt,
                updatedAt: updatedAt,
                artifacts: artifacts
            )
        }
    }

    extension ServerBundleListResponse {
        public static func test(
            bundles: [ServerBundle] = [ServerBundle.test()],
            meta: ServerBundleListMeta? = ServerBundleListMeta.test()
        ) -> ServerBundleListResponse {
            ServerBundleListResponse(
                bundles: bundles,
                meta: meta
            )
        }
    }

    extension ServerBundleListMeta {
        public static func test(
            totalCount: Int = 1,
            pageSize: Int = 20,
            hasNextPage: Bool = false,
            hasPreviousPage: Bool = false
        ) -> ServerBundleListMeta {
            ServerBundleListMeta(
                totalCount: totalCount,
                pageSize: pageSize,
                hasNextPage: hasNextPage,
                hasPreviousPage: hasPreviousPage
            )
        }
    }
#endif
