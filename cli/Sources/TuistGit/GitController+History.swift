import Foundation
import Path

extension GitController {
    public func commitFiles(workingDirectory: AbsolutePath, limit: Int) async throws -> GitCommitFiles {
        guard limit > 0 else { return GitCommitFiles(files: [], truncated: true) }
        let output = try await capture(arguments: ["git", "-C", workingDirectory.pathString, "ls-files", "--stage", "-z"])
        let files = GitHistoryParser.parseCommitFiles(output)
        return GitCommitFiles(files: Array(files.prefix(limit)), truncated: files.count > limit)
    }

    public func gitHistory(
        workingDirectory: AbsolutePath,
        headSHA: String?,
        baseBranch: String?,
        limits: GitHistoryLimits
    ) async throws -> GitHistory {
        let git = ["git", "-C", workingDirectory.pathString]
        let objectFormat = (try? await capture(arguments: git + ["rev-parse", "--show-object-format"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head: String
        if let headSHA {
            head = headSHA
        } else {
            head = try await capture(arguments: git + ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var reasons: [String] = []

        var mergeBase: String?
        if let baseBranch {
            let resolved = await resolveMergeBase(git: git, head: head, baseBranch: baseBranch, limits: limits)
            mergeBase = resolved.sha
            reasons = resolved.reasons
        } else {
            reasons.append("no base branch is known")
        }

        let commits = GitHistoryParser.parseCommits(
            try await capture(
                arguments: git + [
                    "log", "--format=%H %P %ct", "--max-count=\(limits.windowCommits)",
                    "--since=\(limits.windowDays).days.ago", head,
                ]
            )
        )

        var changedFiles: [GitChangedFile] = []
        if let mergeBase {
            // `--no-abbrev`: the raw format abbreviates blob ids by default, and patch coverage
            // matches them against the full ids the coverage rows carry.
            let raw = try await capture(arguments: git + ["diff", "--raw", "--no-abbrev", "-z", "-M", mergeBase, head])
            let unified = try await capture(
                arguments: git + ["diff", "-U0", "-M", "--no-color", "--no-ext-diff", mergeBase, head]
            )
            let (files, dropped) = GitHistoryParser.parseChangedFiles(raw: raw, unified: unified, limits: limits)
            changedFiles = files
            if dropped > 0 {
                reasons.append("\(dropped) changed files beyond the first \(limits.maxChangedFiles) were left out")
            }
        }

        return GitHistory(
            objectFormat: objectFormat.flatMap { $0.isEmpty ? nil : $0 } ?? "sha1",
            headSHA: head,
            baseBranch: baseBranch,
            mergeBaseSHA: mergeBase,
            commits: commits,
            changedFiles: changedFiles,
            fallbackReason: reasons.isEmpty ? nil : reasons.joined(separator: "; ")
        )
    }

    /// The merge base between the head and the base branch, fetching the base ref when the
    /// checkout lacks it and deepening a shallow clone in growing steps until the budget runs out.
    private func resolveMergeBase(
        git: [String],
        head: String,
        baseBranch: String,
        limits: GitHistoryLimits
    ) async -> (sha: String?, reasons: [String]) {
        let deadline = Date().addingTimeInterval(TimeInterval(limits.deepenBudgetSeconds))
        let shallow = (try? await capture(arguments: git + ["rev-parse", "--is-shallow-repository"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"

        func baseRef() async -> String? {
            for candidate in ["origin/\(baseBranch)", baseBranch] {
                let verified = try? await capture(arguments: git + ["rev-parse", "--verify", "--quiet", "\(candidate)^{commit}"])
                guard verified != nil else { continue }
                return candidate
            }
            return nil
        }

        func resolve(_ ref: String) async -> String? {
            let sha = (try? await capture(arguments: git + ["merge-base", ref, head]))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (sha?.isEmpty ?? true) ? nil : sha
        }

        var ref = await baseRef()
        if ref == nil {
            var fetch = git + ["fetch", "--no-tags", "origin", "\(baseBranch):refs/remotes/origin/\(baseBranch)"]
            if shallow { fetch.append("--depth=1") }
            _ = try? await capture(arguments: fetch)
            ref = await baseRef()
        }
        guard let ref else {
            return (nil, ["the base branch \(baseBranch) is not in the checkout and could not be fetched"])
        }

        if let sha = await resolve(ref) { return (sha, []) }
        guard shallow else {
            return (nil, ["\(head.prefix(12)) and \(baseBranch) share no history in the checkout"])
        }

        var depth = 50
        while Date() < deadline {
            _ = try? await capture(arguments: git + ["fetch", "--no-tags", "--deepen=\(depth)", "origin"])
            if let sha = await resolve(ref) { return (sha, []) }
            depth *= 2
        }
        return (nil, ["shallow clone: the merge base with \(baseBranch) was not found within \(limits.deepenBudgetSeconds)s"])
    }
}
