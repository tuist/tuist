import Foundation

public struct GitInfo: Equatable {
    public let ref: String?
    public let branch: String?
    /// The checkout's HEAD: the commit whose files the run built and measured. On a pull request's
    /// merge ref (`refs/pull/N/merge`) that is the merge commit CI checked out, which exists only in
    /// CI. Coverage, test selection, the commit graph and test runs report this commit.
    public let headSHA: String?
    /// The head of the branch the run is for: the pull request's head (the merge commit's second
    /// parent) when HEAD is the merge commit CI made for a pull request, and `headSHA` otherwise.
    /// Report this where the commit must be one the remote's branch has, such as a GitHub check run
    /// or a link to the commit.
    public let branchHeadSHA: String?
    public let remoteURLOrigin: String?
    /// The branch the commit will merge into, as the CI provider reports it for a pull or merge
    /// request; nil outside one, where the project's default branch applies.
    public let baseBranch: String?
    /// The pull or merge request number, when the run is for one.
    public let pullRequestNumber: Int?

    /// - Parameter branchHeadSHA: Defaults to `headSHA`.
    public init(
        ref: String?,
        branch: String?,
        headSHA: String?,
        branchHeadSHA: String? = nil,
        remoteURLOrigin: String?,
        baseBranch: String? = nil,
        pullRequestNumber: Int? = nil
    ) {
        self.ref = ref
        self.branch = branch
        self.headSHA = headSHA
        self.branchHeadSHA = branchHeadSHA ?? headSHA
        self.remoteURLOrigin = remoteURLOrigin
        self.baseBranch = baseBranch
        self.pullRequestNumber = pullRequestNumber
    }

    public static func test(
        ref: String? = nil,
        branch: String? = nil,
        headSHA: String? = nil,
        branchHeadSHA: String? = nil,
        remoteURLOrigin: String? = nil,
        baseBranch: String? = nil,
        pullRequestNumber: Int? = nil
    ) -> GitInfo {
        GitInfo(
            ref: ref,
            branch: branch,
            headSHA: headSHA,
            branchHeadSHA: branchHeadSHA,
            remoteURLOrigin: remoteURLOrigin,
            baseBranch: baseBranch,
            pullRequestNumber: pullRequestNumber
        )
    }
}
