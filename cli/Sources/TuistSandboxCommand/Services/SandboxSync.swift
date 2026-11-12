import Foundation
import Path
import TuistProcess
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Mirrors a local Git worktree into a sandbox, one way, the way Amp mirrors an orb into its Mac satellite: after a sync
/// the sandbox's copy has exactly the worktree's files that Git does not ignore, tracked or not, with their content,
/// executable bits and symbolic links. Git only lists and hashes the files here; the sandbox needs neither Git nor
/// access to the repository's remote, so private repositories and unpushed work need nothing extra.
///
/// Each sync sends a tar of the files whose content or mode changed since the last sync to that path in that sandbox,
/// together with the paths that left the worktree, or the list of every file when this machine does not know what the
/// sandbox holds. The sandbox deletes the files that left. Files it created that were never in the worktree, such as
/// build products, stay. The first sync to a sandbox sends every file.
///
/// One command in the sandbox reports what it holds and then reads the changes from its stdin, so the sandbox never
/// goes idle, and pauses, between the two. A bundle larger than one stdin write goes through the account's storage
/// instead, which the CLI uploads to and the sandbox downloads from at their own bandwidth.
struct SandboxSync {
    struct Result: Codable, Equatable {
        /// The repository's path in the sandbox.
        let root: String
        /// How many files were sent because they are new or changed.
        let changedFiles: Int
        /// The size of what was uploaded.
        let bytes: Int
        /// Whether anything was uploaded, rather than the sandbox having this worktree already.
        let uploaded: Bool

        enum CodingKeys: String, CodingKey {
            case root, bytes, uploaded
            case changedFiles = "changed_files"
        }
    }

    /// A file as Git sees it in the worktree.
    struct Entry: Equatable {
        let mode: String
        let object: String
        let path: String
    }

    /// The sandbox's copy is not the one the changes were computed against.
    private static let staleExitCode = 3
    private static let keptManifests = 20
    /// A large bundle is split into a shard per 8 MB of files, up to 8, each compressed on its own core and uploaded,
    /// downloaded and extracted alongside the others. Smaller bundles stay one archive.
    static let shardBytes = 8 * 1024 * 1024
    static let maxShards = 8

    let remote: SandboxRemote
    let commandRunner: CommandRunning

    /// - Parameter destination: The repository's path in the sandbox. Defaults to `$HOME/work/<repository name>`.
    func sync(repository: AbsolutePath, destination: String?) async throws -> Result {
        let state = try AbsolutePath(
            validating: try await git(["rev-parse", "--path-format=absolute", "--git-path", "tuist-sync"], in: repository)
        )
        let manifests = state.appending(component: "manifests")
        try FileManager.default.createDirectory(atPath: manifests.pathString, withIntermediateDirectories: true)
        let entries = try await worktreeEntries(repository, index: state.appending(component: "index"))
        let manifest = state.appending(component: "manifest.next")
        try Self.serialize(entries).write(to: URL(fileURLWithPath: manifest.pathString))
        let id = try await git(["hash-object", "--no-filters", manifest.pathString], in: repository)

        let destination = destination ?? "$HOME/work/\(repository.basename)"
        var result = try await apply(entries, id: id, manifests: manifests, repository: repository, destination: destination)
        if result == nil {
            // The sandbox's copy moved since the probe, such as through a sync from elsewhere: send everything.
            result = try await apply(entries, id: id, manifests: nil, repository: repository, destination: destination)
        }
        guard let result else {
            throw SandboxCommandError.stepFailed("Syncing the worktree to the sandbox", "The sandbox's copy kept changing.")
        }

        let saved = manifests.appending(component: id)
        try? FileManager.default.removeItem(atPath: saved.pathString)
        try FileManager.default.moveItem(atPath: manifest.pathString, toPath: saved.pathString)
        try Self.prune(manifests)
        return result
    }

    /// The files Git does not ignore, from a scratch index kept between syncs so unchanged files are not hashed again,
    /// and so the user's staging area is never touched. Submodules are left out.
    private func worktreeEntries(_ repository: AbsolutePath, index: AbsolutePath) async throws -> [Entry] {
        if !FileManager.default.fileExists(atPath: index.pathString) {
            // Starting from the real index reuses its cached file metadata, so the first sync hashes only changed files.
            let realIndex = try await git(["rev-parse", "--path-format=absolute", "--git-path", "index"], in: repository)
            try? FileManager.default.copyItem(atPath: realIndex, toPath: index.pathString)
        }
        let environment = ["GIT_INDEX_FILE": index.pathString]
        _ = try await git(["add", "-A"], in: repository, environment: environment)
        // Not trimmed like other Git output, because a path can end with whitespace.
        let listing = try await commandRunner.run(
            arguments: ["git", "-C", repository.pathString, "ls-files", "-s", "-z"],
            environment: ProcessInfo.processInfo.environment.merging(environment) { $1 }
        ).concatenatedString(including: [.standardOutput])
        return Self.entries(fromIndexListing: listing)
    }

    /// Runs one command in the sandbox that reports which worktree its copy holds and then waits on its stdin for what
    /// to change, so the sandbox has no idle gap to pause in between. Sends the changes against the manifests in
    /// `manifests`, or every file when it is nil or has no manifest for the sandbox's copy. Returns nil when the changes
    /// no longer apply because the sandbox's copy changed meanwhile.
    private func apply(
        _ entries: [Entry],
        id: String,
        manifests: AbsolutePath?,
        repository: AbsolutePath,
        destination: String
    ) async throws -> Result? {
        let command = try await remote.start(
            Self.applyScript,
            environment: ["TUIST_DEST": destination, "TUIST_ID": id],
            stdin: true,
            timeoutMs: 60 * 60 * 1000
        )
        let (probes, probed) = AsyncStream.makeStream(of: String.self)
        let output = Task { [remote] in
            defer { probed.finish() }
            var stdout = ""
            var stderr = ""
            var reported = false
            let exit = try await remote.follow(command.id) { isStandardError, data in
                if isStandardError { stderr += data; return }
                stdout += data
                if !reported, stdout.contains("\nprobed\n") {
                    reported = true
                    probed.yield(stdout)
                }
            }
            return SandboxRemote.Captured(exit: exit, stdout: stdout, stderr: stderr)
        }
        do {
            var iterator = probes.makeAsyncIterator()
            guard let probe = await iterator.next(), case let (root, remoteID)? = Self.probe(probe) else {
                let captured = try await output.value
                throw SandboxCommandError.stepFailed("Preparing \(destination) in the sandbox", captured.stdout + captured.stderr)
            }
            if remoteID == id {
                try await remote.writeStdin(command.id, Data("skip\n".utf8))
                try Self.check(try await output.value)
                return Result(root: root, changedFiles: 0, bytes: 0, uploaded: false)
            }
            let previous = manifests.flatMap { manifests in
                remoteID.flatMap { try? Data(contentsOf: URL(fileURLWithPath: manifests.appending(component: $0).pathString)) }
            }.map(Self.entries)
            let changes = Self.changes(from: previous, to: entries)

            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("tuist-sandbox-sync-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: scratch) }
            let kind = previous == nil ? "full" : "delta"
            let shards = Self.shards(
                Self.sizes(of: changes, in: repository),
                cores: ProcessInfo.processInfo.activeProcessorCount
            )
            let bytes: Int
            if shards.count > 1, let sent = try await sendShards(
                shards,
                kind: kind,
                entries: entries,
                previous: previous,
                repository: repository,
                scratch: scratch,
                commandID: command.id
            ) {
                bytes = sent
            } else {
                let archive = try await bundle(
                    changes.map(\.path),
                    of: entries,
                    previous: previous,
                    repository: repository,
                    in: scratch
                )
                bytes = try Self.size(of: archive)
                let inline = "inline \(kind)\n"
                if bytes + inline.utf8.count > SandboxRemote.stdinChunkBytes, let url = try await remote.stage(archive) {
                    try await remote.writeStdin(command.id, Data("url \(kind) \(url.absoluteString)\n".utf8))
                } else {
                    try await remote.writeStdin(command.id, Data(inline.utf8), file: archive)
                }
            }
            let captured = try await output.value
            if captured.exit.exitCode == Self.staleExitCode, previous != nil { return nil }
            try Self.check(captured)
            return Result(root: root, changedFiles: changes.count, bytes: bytes, uploaded: true)
        } catch {
            output.cancel()
            try? await remote.cancel(command.id)
            throw error
        }
    }

    /// Sends the bundle in parts through storage, so compressing, uploading, downloading and extracting overlap: first the
    /// paths, which the sandbox applies while the files are on their way, then each of `shards`, compressed and uploaded in
    /// parallel and named on the command's stdin as soon as it is uploaded, which the sandbox then downloads and extracts
    /// alongside the others. Returns what it uploaded, or nil, having sent nothing, when the server has no uploads.
    private func sendShards(
        _ shards: [[String]],
        kind: String,
        entries: [Entry],
        previous: [Entry]?,
        repository: AbsolutePath,
        scratch: URL,
        commandID: String
    ) async throws -> Int? {
        let paths = try await bundle(nil, of: entries, previous: previous, repository: repository, in: scratch)
        guard let pathsURL = try await remote.stage(paths) else { return nil }
        let (uploads, uploaded) = AsyncThrowingStream.makeStream(of: (url: URL, bytes: Int).self)
        let producer = Task { [self] in
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (index, files) in shards.enumerated() {
                        group.addTask {
                            let archive = scratch.appendingPathComponent("shard-\(index).tar.gz")
                            let list = scratch.appendingPathComponent("shard-\(index)")
                            try await compress(files, from: repository, to: archive, list: list)
                            guard let url = try await remote.stage(archive) else {
                                throw SandboxCommandError.stepFailed("Uploading the worktree", "Tuist stopped accepting uploads.")
                            }
                            let bytes = try Self.size(of: archive)
                            uploaded.yield((url, bytes))
                        }
                    }
                    try await group.waitForAll()
                }
                uploaded.finish()
            } catch {
                uploaded.finish(throwing: error)
            }
        }
        defer { producer.cancel() }

        var bytes = try Self.size(of: paths)
        try await remote.writeStdin(commandID, Data("shards \(kind) \(pathsURL.absoluteString)\n".utf8), close: false)
        var sent = 0
        for try await upload in uploads {
            sent += 1
            bytes += upload.bytes
            try await remote.writeStdin(commandID, Data("\(upload.url.absoluteString)\n".utf8), close: sent == shards.count)
        }
        return bytes
    }

    /// Writes the bundle the sandbox applies: a tar of either `paths.gz`, every file's path, or, when the sandbox has
    /// `previous`, `deleted` and `added`, the paths that left and joined it, and, unless `files` is nil, `files.tar.gz`,
    /// the new and changed files.
    private func bundle(
        _ files: [String]?,
        of entries: [Entry],
        previous: [Entry]?,
        repository: AbsolutePath,
        in scratch: URL
    ) async throws -> URL {
        let bundle = scratch.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        func write(_ paths: [String], to name: String) throws {
            try Data(paths.map { $0 + "\0" }.joined().utf8).write(to: bundle.appendingPathComponent(name))
        }
        var names: [String]
        if let previous {
            let delta = Self.delta(from: previous, to: entries)
            try write(delta.deleted, to: "deleted")
            try write(delta.added, to: "added")
            names = ["deleted", "added"]
        } else {
            try write(entries.map(\.path), to: "paths")
            try await commandRunner.run(arguments: ["gzip", "-n", bundle.appendingPathComponent("paths").path])
                .awaitCompletion()
            names = ["paths.gz"]
        }
        if let files {
            try await compress(
                files,
                from: repository,
                to: bundle.appendingPathComponent("files.tar.gz"),
                list: scratch.appendingPathComponent("changed")
            )
            names.append("files.tar.gz")
        }
        let archive = scratch.appendingPathComponent("bundle.tar")
        try await commandRunner.run(
            arguments: ["tar", "-cf", archive.path, "-C", bundle.path] + names,
            environment: Self.tarEnvironment
        )
        .awaitCompletion()
        return archive
    }

    /// Writes a gzipped tar of `files`, relative to `repository`, listing them in `list` first.
    private func compress(_ files: [String], from repository: AbsolutePath, to archive: URL, list: URL) async throws {
        try Data(files.map { $0 + "\0" }.joined().utf8).write(to: list)
        try await commandRunner.run(
            arguments: ["tar", "-czf", archive.path, "-C", repository.pathString, "--null", "-T", list.path],
            environment: Self.tarEnvironment
        ).awaitCompletion()
    }

    /// COPYFILE_DISABLE keeps macOS's tar from adding AppleDouble `._` entries for extended attributes.
    private static var tarEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.merging(["COPYFILE_DISABLE": "1"]) { $1 }
    }

    private static func size(of file: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
    }

    /// What each entry adds to a tar: its size on disk, or nothing when it is gone, plus a header.
    static func sizes(of entries: [Entry], in repository: AbsolutePath) -> [(path: String, bytes: Int)] {
        entries.map { entry in
            var info = stat()
            let bytes = lstat(repository.pathString + "/" + entry.path, &info) == 0 ? Int(info.st_size) : 0
            return (entry.path, bytes + 512)
        }
    }

    /// Splits `files` into consecutive runs of about the same size, so each compresses on a core of its own while
    /// directories stay together: one run per `shardBytes`, at most one per core and `maxShards`.
    static func shards(_ files: [(path: String, bytes: Int)], cores: Int) -> [[String]] {
        let total = files.reduce(0) { $0 + $1.bytes }
        let count = max(1, min(total / shardBytes, cores, maxShards))
        var shards: [[String]] = [[]]
        var accumulated = 0
        for file in files {
            if shards.count < count, accumulated * count >= total * shards.count {
                shards.append([])
            }
            shards[shards.count - 1].append(file.path)
            accumulated += file.bytes
        }
        return shards
    }

    /// Reports the copy's absolute path and the worktree it holds (`root`, `id`, then `probed`), or no worktree when
    /// files it was sent are missing, then reads a header
    /// line from stdin: `skip`, `inline <kind>` followed by the bundle, `url <kind> <url>` to download the bundle from,
    /// or `shards <kind> <url>` to download a bundle without `files.tar.gz`, followed by a line per shard of the files
    /// with its URL, each downloaded and extracted alongside the others as soon as it is named. A `delta` bundle exits
    /// with `staleExitCode` when the copy changed since it was probed. It deletes the files that left the worktree, and
    /// the directories that leaves empty, before extracting the new and changed ones.
    private static let applyScript = #"""
    set -euo pipefail
    case "$TUIST_DEST" in '$HOME'*) root="$HOME${TUIST_DEST#'$HOME'}" ;; *) root="$TUIST_DEST" ;; esac
    mkdir -p "$root"
    root=$(cd "$root" && pwd -P)
    state="$HOME/.tuist-sync/$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
    probed=$(cat "$state/id" 2> /dev/null || true)
    # The record lives outside the copy, so a copy that lost files it was sent, such as one deleted to start over,
    # is reported as unknown and gets every file again.
    if [ -n "$probed" ] && ! (cd "$root" && perl -e '
      local $/ = "\0";
      open my $f, "<", $ARGV[0] or exit 1;
      while (<$f>) { chomp; lstat or exit 1 }
    ' "$state/paths"); then
      probed=
    fi
    printf 'root %s\nid %s\nprobed\n' "$root" "$probed"
    IFS=' ' read -r action kind url || true
    case "$action" in inline | url | shards) ;; *) exit 0 ;; esac
    work=$(mktemp -d "${TMPDIR:-/tmp}/tuist-sync.XXXXXX")
    # Shard URLs may still be arriving when this exits early, such as when the copy is stale: reading them keeps the
    # client's writes going until it reads the exit status and the error.
    trap 'cat > /dev/null; rm -rf "$work"' EXIT
    if [ "$action" = inline ]; then
      cat > "$work/bundle.tar"
    else
      curl -fsS --retry 3 -o "$work/bundle.tar" "$url"
    fi
    if [ "$kind" = delta ] && [ "$(cat "$state/id" 2> /dev/null || true)" != "$probed" ]; then
      exit \#(SandboxSync.staleExitCode)
    fi
    tar -xf "$work/bundle.tar" -C "$work"
    mkdir -p "$state"
    cd "$root"
    apply='
      sub records {
        my ($file) = @_;
        open my $f, "<", $file or die "$file: $!";
        local $/ = "\0";
        my @records = <$f>;
        chomp @records;
        @records;
      }
      sub remove {
        for (@_) {
          unlink $_;
          my $dir = $_;
          while ($dir =~ s{/[^/]*\z}{} && rmdir $dir) {}
        }
      }
      my ($kind, $old, $list, $added) = @ARGV;
      if ($kind eq "full") {
        my %keep = map { $_ => 1 } records($list);
        remove(grep { !$keep{$_} } records($old)) if -e $old;
      } else {
        my @gone = records($list);
        my %gone = map { $_ => 1 } @gone;
        remove(@gone);
        print map { "$_\0" } (grep { !$gone{$_} } records($old)), records($added);
      }
    '
    if [ "$kind" = full ]; then
      gunzip "$work/paths.gz"
      perl -e "$apply" full "$state/paths" "$work/paths"
    else
      perl -e "$apply" delta "$state/paths" "$work/deleted" "$work/added" > "$work/paths"
    fi
    if [ -e "$work/files.tar.gz" ]; then tar -xzf "$work/files.tar.gz"; fi
    # Each shard streams into tar while it downloads. A failed attempt is extracted again from the start, which
    # overwrites what it left, since curl cannot retry into a pipe.
    shards=
    while IFS= read -r shard; do
      (
        for attempt in 1 2 3; do
          if curl -fsS "$shard" | tar -xzf -; then exit 0; fi
          sleep "$attempt"
        done
        exit 1
      ) &
      shards="$shards $!"
    done
    for shard in $shards; do wait "$shard"; done
    mv "$work/paths" "$state/paths"
    printf '%s' "$TUIST_ID" > "$state/id"
    """#

    /// Parses the probe's `root <path>` and `id <id>` lines.
    static func probe(_ stdout: String) -> (root: String, id: String?)? {
        let lines = stdout.split(separator: "\n").map(String.init)
        guard let root = lines.first(where: { $0.hasPrefix("root ") })?.dropFirst(5),
              let id = lines.first(where: { $0.hasPrefix("id ") || $0 == "id" })
        else { return nil }
        let value = id.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return (String(root), value.isEmpty ? nil : value)
    }

    private static func check(_ captured: SandboxRemote.Captured) throws {
        guard captured.exit.exitCode == 0 else {
            throw SandboxCommandError.stepFailed("Syncing the worktree to the sandbox", captured.stderr)
        }
    }

    /// The paths that left the worktree since `previous`, and those that joined it.
    static func delta(from previous: [Entry], to entries: [Entry]) -> (deleted: [String], added: [String]) {
        let before = Set(previous.map(\.path))
        let after = Set(entries.map(\.path))
        return (previous.map(\.path).filter { !after.contains($0) }, entries.map(\.path).filter { !before.contains($0) })
    }

    /// The entries to send: every one when the sandbox's previous worktree is unknown, otherwise the new ones and those
    /// whose content or mode changed.
    static func changes(from previous: [Entry]?, to entries: [Entry]) -> [Entry] {
        guard let previous else { return entries }
        let known = Dictionary(previous.map { ($0.path, $0) }, uniquingKeysWith: { $1 })
        return entries.filter { known[$0.path] != $0 }
    }

    /// Parses `git ls-files -s -z` output (`<mode> <object> <stage>\t<path>\0`), leaving out submodules.
    static func entries(fromIndexListing listing: String) -> [Entry] {
        listing.split(separator: "\0").compactMap { record in
            guard let tab = record.firstIndex(of: "\t") else { return nil }
            let fields = record[..<tab].split(separator: " ")
            guard fields.count >= 2, fields[0] != "160000" else { return nil }
            return Entry(mode: String(fields[0]), object: String(fields[1]), path: String(record[record.index(after: tab)...]))
        }
    }

    /// The manifest saved between syncs: `<mode> <object>\t<path>\0` per entry.
    static func serialize(_ entries: [Entry]) -> Data {
        Data(entries.map { "\($0.mode) \($0.object)\t\($0.path)\0" }.joined().utf8)
    }

    static func entries(_ manifest: Data) -> [Entry] {
        entries(fromIndexListing: String(decoding: manifest, as: UTF8.self))
    }

    private static func prune(_ manifests: AbsolutePath) throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: manifests.pathString)
            .map { manifests.appending(component: $0) }
        let byAge = files.sorted {
            let first = (try? FileManager.default.attributesOfItem(atPath: $0.pathString)[.modificationDate] as? Date) ??
                .distantPast
            let second = (try? FileManager.default.attributesOfItem(atPath: $1.pathString)[.modificationDate] as? Date) ??
                .distantPast
            return first > second
        }
        for file in byAge.dropFirst(keptManifests) {
            try? FileManager.default.removeItem(atPath: file.pathString)
        }
    }

    private func git(_ arguments: [String], in repository: AbsolutePath, environment: [String: String] = [:]) async throws
        -> String
    {
        try await commandRunner.run(
            arguments: ["git", "-C", repository.pathString] + arguments,
            environment: ProcessInfo.processInfo.environment.merging(environment) { $1 }
        )
        .concatenatedString(including: [.standardOutput])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
