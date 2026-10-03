import Foundation
import Path

extension GitController {
    public func commitFiles(workingDirectory: AbsolutePath, sha: String, limit: Int) async throws -> GitCommitFiles {
        guard limit > 0 else { return GitCommitFiles(files: [], truncated: true) }
        // The commit's tree rather than the index: on a pull request's merge checkout the run
        // reports the pull request's head, while the index is the merge commit's.
        let output = try await capture(
            arguments: ["git", "-C", workingDirectory.pathString, "ls-tree", "-r", "-z", "--full-tree", sha]
        )
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

        let commits = try await windowCommits(git: git, workingDirectory: workingDirectory, head: head, limits: limits)

        var changedFiles: [GitChangedFile] = []
        if let mergeBase {
            // `--no-abbrev`: the raw format abbreviates blob ids by default, and patch coverage
            // matches them against the full ids the coverage rows carry.
            let raw = try await capture(arguments: git + ["diff", "--raw", "--no-abbrev", "-z", "-M", mergeBase, head])
            // The hunks are keyed by the `+++ b/<path>` headers, so they must not depend on the
            // user's config: prefixes (`diff.noprefix`, `diff.mnemonicPrefix`) and quoting.
            let unified = try await capture(
                arguments: git + [
                    "-c", "core.quotePath=false", "diff", "-U0", "-M", "--no-color", "--no-ext-diff",
                    "--src-prefix=a/", "--dst-prefix=b/", mergeBase, head,
                ]
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

    /// The commits reachable from the head within the window, less a shallow clone's boundary
    /// commits (its `shallow` file): `git log` lists them without the parents they have, which
    /// the server would store as roots for good, while leaving them out lets a deeper checkout
    /// upload them.
    private func windowCommits(
        git: [String],
        workingDirectory: AbsolutePath,
        head: String,
        limits: GitHistoryLimits
    ) async throws -> [GitHistoryCommit] {
        let output = try await capture(
            arguments: git + [
                "log", "--format=%H %P %ct", "--max-count=\(limits.windowCommits)",
                "--since=\(limits.windowDays).days.ago", head,
            ]
        )
        guard let shallowFile = try? await capture(arguments: git + ["rev-parse", "--git-path", "shallow"]),
              let path = try? AbsolutePath(
                  validating: shallowFile.trimmingCharacters(in: .whitespacesAndNewlines),
                  relativeTo: workingDirectory
              ),
              let boundary = try? String(contentsOfFile: path.pathString, encoding: .utf8)
        else { return GitHistoryParser.parseCommits(output) }
        let boundarySHAs = Set(boundary.split(whereSeparator: \.isNewline).map(String.init))
        return GitHistoryParser.parseCommits(output).filter { !boundarySHAs.contains($0.sha) }
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

        // Only commits and trees place the merge base, and blobs are most of what a fetch carries.
        // `--filter=tree:0` would leave the trees out too, but Git 2.50 aborts deepening with it
        // (`BUG: should_include_obj should only be called on existing objects`). A server without
        // filters ignores the option with a warning and sends everything.
        let baseRefspec = "+\(baseBranch):refs/remotes/origin/\(baseBranch)"
        var ref = await baseRef()
        if ref == nil {
            var fetch = git + ["fetch", "--no-tags", "--filter=blob:none"]
            if shallow { fetch.append("--depth=1") }
            fetch += ["origin", baseRefspec]
            if await self.fetch(arguments: fetch, deadline: deadline) == .timedOut {
                return (nil, [
                    "the base branch \(baseBranch) is not in the checkout and could not be fetched within \(limits.deepenBudgetSeconds)s",
                ])
            }
            ref = await baseRef()
        }
        guard let ref else {
            return (nil, ["the base branch \(baseBranch) is not in the checkout and could not be fetched"])
        }

        if let sha = await resolve(ref) { return (sha, []) }
        guard shallow else {
            return (nil, ["\(head.prefix(12)) and \(baseBranch) share no history in the checkout"])
        }

        // The base branch is named on every deepen: without a refspec git fetches what the
        // checkout's config says, which for `actions/checkout` is every branch of the repository,
        // with however much history each has (0.8-1.1 GiB per run on tuist/tuist, measured).
        // Deepening is relative to the current boundary, so the steps add up, and together they
        // stay within the history window. Never past a fetch that failed either: a deepen that
        // fails immediately, offline or against a remote that refuses it, returns before the
        // budget is spent and would otherwise be retried until the budget ran out.
        let maxDepth = max(limits.windowCommits, 50)
        var depth = 0
        var step = 50
        while Date() < deadline, depth < maxDepth {
            step = min(step, maxDepth - depth)
            let deepen = git + ["fetch", "--no-tags", "--filter=blob:none", "--deepen=\(step)", "origin", baseRefspec]
            guard await fetch(arguments: deepen, deadline: deadline) == .succeeded else { break }
            if let sha = await resolve(ref) { return (sha, []) }
            depth += step
            step *= 2
        }
        return (nil, ["shallow clone: the merge base with \(baseBranch) was not found within \(limits.deepenBudgetSeconds)s"])
    }

    private enum FetchOutcome {
        case succeeded, failed, timedOut
    }

    /// Runs the fetch until it exits or the deadline passes, whichever comes first. A fetch still
    /// running at the deadline is torn down together with the processes it started
    /// (`git-remote-https`, `ssh`, `index-pack`), which a stalled remote would otherwise keep alive.
    private func fetch(arguments: [String], deadline: Date) async -> FetchOutcome {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return .timedOut }
        return await withTaskGroup(of: FetchOutcome?.self) { group in
            group.addTask {
                do {
                    try await runInOwnProcessGroup(arguments: arguments).awaitCompletion()
                } catch {
                    return .failed
                }
                // A cancelled run's stream ends without an error, so it would read as a success.
                return Task.isCancelled ? nil : .succeeded
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(remaining))
                return Task.isCancelled ? nil : .timedOut
            }
            let outcome = await group.next() ?? nil
            group.cancelAll()
            return outcome ?? .timedOut
        }
    }
}
