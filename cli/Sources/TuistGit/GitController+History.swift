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

        // Never deeper than the history window, and never past a fetch that
        // failed: a deepen that fails immediately, offline or against a remote
        // that refuses it, returns before the budget is spent and would
        // otherwise leave this doubling `depth` until it overflows.
        //
        // No object filter here. `--filter=tree:0` is what deepening would want,
        // since only commits are needed to place the merge base, but Git 2.50
        // aborts on it (`BUG: should_include_obj should only be called on
        // existing objects`) because deepening reads the trees it just excluded.
        // `--filter=blob:none` survives, and measured against this repository it
        // transfers 20-35x more than an unfiltered deepen: the remote cannot
        // reuse its packs for a filtered request, so it sends a freshly built
        // one, and omitting blobs does not come close to paying for that.
        let maxDepth = max(limits.windowCommits, 50)
        var depth = 50
        while Date() < deadline {
            guard (try? await capture(arguments: git + ["fetch", "--no-tags", "--deepen=\(depth)", "origin"])) != nil
            else { break }
            if let sha = await resolve(ref) { return (sha, []) }
            if depth >= maxDepth { break }
            depth = min(depth * 2, maxDepth)
        }
        return (nil, ["shallow clone: the merge base with \(baseBranch) was not found within \(limits.deepenBudgetSeconds)s"])
    }
}
