import Foundation
import Path
import TuistProcess

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
        let deadline = Date().addingTimeInterval(TimeInterval(limits.deepenBudgetSeconds))

        var headInCheckout = await fetchMissingHead(git: git, head: head, limits: limits, deadline: deadline)

        var mergeBase: String?
        var baseHead: String?
        var localBaseHead: String?
        if let baseBranch {
            let resolved = await resolveMergeBase(
                git: git,
                head: head,
                baseBranch: baseBranch,
                limits: limits,
                deadline: deadline
            )
            mergeBase = resolved.sha
            reasons = resolved.reasons
            // Read after any deepening, which fetches the base branch again and can move it.
            if let ref = resolved.ref {
                localBaseHead = await commitSHA(git: git, ref: ref)
                baseHead = localBaseHead
            } else if limits.remoteAccess == .baseHead {
                baseHead = await remoteBranchHead(git: git, branch: baseBranch, budgetSeconds: limits.deepenBudgetSeconds)
            }
        } else {
            reasons.append("no base branch is known")
        }

        // A deepen for the merge base can bring a missing head in.
        if !headInCheckout { headInCheckout = await commitSHA(git: git, ref: head) != nil }
        if !headInCheckout { reasons.append("\(head.prefix(12)) is not in the checkout") }
        // Without it, the walk starts at the checkout's HEAD, as it did before the head was reported.
        let walkHead = headInCheckout ? head : await commitSHA(git: git, ref: "HEAD")
        let heads = [walkHead].compactMap { $0 } + [localBaseHead].compactMap { $0 }.filter { $0 != walkHead }
        let commits = heads.isEmpty ? [] : try await windowCommits(
            git: git, workingDirectory: workingDirectory, heads: heads, limits: limits
        )

        return GitHistory(
            objectFormat: objectFormat.flatMap { $0.isEmpty ? nil : $0 } ?? "sha1",
            headSHA: head,
            baseBranch: baseBranch,
            mergeBaseSHA: mergeBase,
            baseHeadSHA: baseHead,
            commits: commits,
            fallbackReason: reasons.isEmpty ? nil : reasons.joined(separator: "; ")
        )
    }

    /// On a pull request's merge checkout the head is the merge commit's second parent, which a
    /// depth-1 clone does not contain: it is fetched alone, without blobs, within the budget.
    /// Returns whether the checkout has it.
    private func fetchMissingHead(git: [String], head: String, limits: GitHistoryLimits, deadline: Date) async -> Bool {
        if await commitSHA(git: git, ref: head) != nil { return true }
        guard limits.remoteAccess == .history else { return false }
        let fetch = git + ["fetch", "--no-tags", "--recurse-submodules=no", "--filter=blob:none", "--depth=1", "origin", head]
        guard await self.fetch(arguments: fetch, deadline: deadline) == .succeeded else { return false }
        return await commitSHA(git: git, ref: head) != nil
    }

    private func commitSHA(git: [String], ref: String) async -> String? {
        let sha = (try? await capture(arguments: git + ["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (sha?.isEmpty ?? true) ? nil : sha
    }

    /// The commits reachable from the heads within the window. `git log` lists a shallow clone's
    /// boundary commits (its `shallow` file) without parents, so theirs are read from the commit
    /// objects, which the raw format prints regardless of the shallow grafts. In a depth-1 clone
    /// the head is such a commit. When they cannot be read, the boundary commits are left out
    /// rather than stored as roots.
    private func windowCommits(
        git: [String],
        workingDirectory: AbsolutePath,
        heads: [String],
        limits: GitHistoryLimits
    ) async throws -> [GitHistoryCommit] {
        let output = try await capture(
            arguments: git + [
                "log", "--format=%H %P %ct", "--max-count=\(limits.windowCommits)",
                "--since=\(limits.windowDays).days.ago",
            ] + heads
        )
        guard let shallowFile = try? await capture(arguments: git + ["rev-parse", "--git-path", "shallow"]),
              let path = try? AbsolutePath(
                  validating: shallowFile.trimmingCharacters(in: .whitespacesAndNewlines),
                  relativeTo: workingDirectory
              ),
              let boundary = try? String(contentsOfFile: path.pathString, encoding: .utf8)
        else { return GitHistoryParser.parseCommits(output) }
        let boundarySHAs = Set(boundary.split(whereSeparator: \.isNewline).map(String.init))
        let commits = GitHistoryParser.parseCommits(output)
        let windowBoundary = commits.map(\.sha).filter(boundarySHAs.contains)
        guard !windowBoundary.isEmpty else { return commits }

        let raw = try? await capture(arguments: git + ["log", "--no-walk", "--no-decorate", "--format=raw"] + windowBoundary)
        let parents = raw.map(GitHistoryParser.parseRawParents) ?? [:]
        return commits.compactMap { commit in
            guard boundarySHAs.contains(commit.sha) else { return commit }
            guard let real = parents[commit.sha] else { return nil }
            return GitHistoryCommit(sha: commit.sha, parents: real, committedAt: commit.committedAt)
        }
    }

    /// The merge base between the head and the base branch, fetching the base ref when the
    /// checkout lacks it and deepening a shallow clone in growing steps until the budget runs out.
    private func resolveMergeBase(
        git: [String],
        head: String,
        baseBranch: String,
        limits: GitHistoryLimits,
        deadline: Date
    ) async -> MergeBaseResolution {
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
        if ref == nil, limits.remoteAccess != .history {
            return MergeBaseResolution(sha: nil, ref: nil, reasons: ["the base branch \(baseBranch) is not in the checkout"])
        }
        if ref == nil {
            var fetch = git + ["fetch", "--no-tags", "--recurse-submodules=no", "--filter=blob:none"]
            if shallow { fetch.append("--depth=1") }
            fetch += ["origin", baseRefspec]
            if await self.fetch(arguments: fetch, deadline: deadline) == .timedOut {
                return MergeBaseResolution(sha: nil, ref: nil, reasons: [
                    "the base branch \(baseBranch) is not in the checkout and could not be fetched within \(limits.deepenBudgetSeconds)s",
                ])
            }
            ref = await baseRef()
        }
        guard let ref else {
            return MergeBaseResolution(
                sha: nil,
                ref: nil,
                reasons: ["the base branch \(baseBranch) is not in the checkout and could not be fetched"]
            )
        }

        if let sha = await resolve(ref) { return MergeBaseResolution(sha: sha, ref: ref, reasons: []) }
        guard shallow else {
            return MergeBaseResolution(
                sha: nil,
                ref: ref,
                reasons: ["\(head.prefix(12)) and \(baseBranch) share no history in the checkout"]
            )
        }
        guard limits.remoteAccess == .history else {
            return MergeBaseResolution(
                sha: nil,
                ref: ref,
                reasons: ["shallow clone: the merge base with \(baseBranch) is not in the checkout"]
            )
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
            let deepen = git + [
                "fetch",
                "--no-tags",
                "--recurse-submodules=no",
                "--filter=blob:none",
                "--deepen=\(step)",
                "origin",
                baseRefspec,
            ]
            guard await fetch(arguments: deepen, deadline: deadline) == .succeeded else { break }
            if let sha = await resolve(ref) { return MergeBaseResolution(sha: sha, ref: ref, reasons: []) }
            depth += step
            step *= 2
        }
        return MergeBaseResolution(
            sha: nil,
            ref: ref,
            reasons: ["shallow clone: the merge base with \(baseBranch) was not found within \(limits.deepenBudgetSeconds)s"]
        )
    }

    /// The merge base, the base branch's ref it was resolved against, and why either is missing.
    private struct MergeBaseResolution {
        let sha: String?
        let ref: String?
        let reasons: [String]
    }

    private enum FetchOutcome {
        case succeeded, failed, timedOut
    }

    /// The branch's latest commit as the remote has it: one `git ls-remote`, which transfers no
    /// objects, torn down like a fetch when it outlasts the budget.
    private func remoteBranchHead(git: [String], branch: String, budgetSeconds: Int) async -> String? {
        let arguments = git + ["ls-remote", "origin", "refs/heads/\(branch)"]
        let output = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var bytes: [UInt8] = []
                do {
                    for try await event in runInOwnProcessGroup(arguments: arguments) {
                        if case let .standardOutput(chunk) = event { bytes += chunk }
                    }
                } catch {
                    return nil
                }
                return Task.isCancelled ? nil : String(bytes: bytes, encoding: .utf8)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(budgetSeconds))
                return nil
            }
            let output = await group.next() ?? nil
            group.cancelAll()
            return output
        }
        return output?.split(whereSeparator: \.isWhitespace).first.map(String.init)
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
