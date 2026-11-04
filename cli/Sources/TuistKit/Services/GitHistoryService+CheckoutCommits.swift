import Foundation
import Path
import TuistGit

extension GitHistoryService {
    public func uploadCheckoutCommits(
        gitInfo: GitInfo,
        workingDirectory: AbsolutePath,
        fullHandle: String,
        serverURL: URL,
        coverage: Bool
    ) async {
        guard Self.enabled(coverage: coverage) else { return }
        // Not cached: the checkout may have been deepened since the run's history was collected.
        let collected = await collectFromCheckout(
            gitInfo: gitInfo,
            workingDirectory: workingDirectory,
            fullHandle: fullHandle,
            serverURL: serverURL,
            coverage: coverage,
            remoteAccess: GitHistoryRemoteAccess.none
        )
        guard let repositoryURL = collected.repositoryURL, !repositoryURL.isEmpty else { return }
        do {
            try await uploadCommits(
                collected,
                repositoryURL: repositoryURL,
                fullHandle: fullHandle,
                serverURL: serverURL,
                branchHeads: false
            )
        } catch {
            Self.warn("The checkout's Git history could not be uploaded: \(error.localizedDescription)", coverage: coverage)
        }
    }
}
