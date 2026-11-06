import Foundation

public struct GitInfo: Equatable {
    public let ref: String?
    public let branch: String?
    public let sha: String?
    public let remoteURLOrigin: String?
    /// The branch the commit will merge into, as the CI provider reports it for a pull or merge
    /// request; nil outside one, where the project's default branch applies.
    public let baseBranch: String?
    /// The pull or merge request number, when the run is for one.
    public let pullRequestNumber: Int?

    public init(
        ref: String?,
        branch: String?,
        sha: String?,
        remoteURLOrigin: String?,
        baseBranch: String? = nil,
        pullRequestNumber: Int? = nil
    ) {
        self.ref = ref
        self.branch = branch
        self.sha = sha
        self.remoteURLOrigin = remoteURLOrigin
        self.baseBranch = baseBranch
        self.pullRequestNumber = pullRequestNumber
    }

    public static func test(
        ref: String? = nil,
        branch: String? = nil,
        sha: String? = nil,
        remoteURLOrigin: String? = nil,
        baseBranch: String? = nil,
        pullRequestNumber: Int? = nil
    ) -> GitInfo {
        GitInfo(
            ref: ref,
            branch: branch,
            sha: sha,
            remoteURLOrigin: remoteURLOrigin,
            baseBranch: baseBranch,
            pullRequestNumber: pullRequestNumber
        )
    }
}
