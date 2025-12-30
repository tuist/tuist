import Foundation

public struct GitInfo: Equatable {
    public let ref: String?
    public let branch: String?
    public let sha: String?
    public let remoteURLOrigin: String?

    public init(
        ref: String?,
        branch: String?,
        sha: String?,
        remoteURLOrigin: String?
    ) {
        self.ref = ref
        self.branch = branch
        self.sha = sha
        self.remoteURLOrigin = remoteURLOrigin
    }
}

extension GitInfo {
    public static func test(
        ref: String? = nil,
        branch: String? = nil,
        sha: String? = nil,
        remoteURLOrigin: String? = nil
    ) -> GitInfo {
        GitInfo(
            ref: ref,
            branch: branch,
            sha: sha,
            remoteURLOrigin: remoteURLOrigin
        )
    }
}
