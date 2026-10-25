import Foundation

/// Export through a private index and an empty work tree. Neither a dirty native index nor
/// its working-tree attributes can change the bytes stamped with the resolved pin.
enum PinnedSourceSnapshot {
    private static var gitEnvironment: [String: String] {
        Environment.current.filter { ![
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_NAMESPACE",
            "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_ATTR_SOURCE",
        ].contains($0.key) }.merging(SystemProcess.nonInteractiveGitEnvironment) { _, value in value }
            .merging(["GIT_OPTIONAL_LOCKS": "0"]) { _, value in value }
    }

    static func write(from checkout: URL, revision: String, to destination: URL, staging: URL) async throws {
        let gitDir = try await SystemProcess.output(
            "/usr/bin/git", ["-C", checkout.path, "rev-parse", "--absolute-git-dir"],
            customEnvironment: gitEnvironment
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try await export(
            gitDirectory: URL(fileURLWithPath: gitDir), nativeDirectory: checkout,
            revision: revision, destination: destination, staging: staging
        )
    }

    private static func export(
        gitDirectory: URL, nativeDirectory: URL, revision: String,
        destination: URL, staging: URL
    ) async throws {
        try await fileSystem.makeDirectory(at: destination.absolutePath, options: [.createTargetParentDirectories])
        var environment = gitEnvironment
        environment["GIT_DIR"] = gitDirectory.path
        environment["GIT_WORK_TREE"] = destination.path
        environment["GIT_INDEX_FILE"] = staging.appendingPathComponent("index-\(UUID().uuidString)").path
        environment["GIT_ATTR_SOURCE"] = revision
        let options = [
            "-c", "core.sparseCheckout=false", "-c", "core.sparseCheckoutCone=false",
            "-c", "index.sparse=false", "-c", "core.fsmonitor=false",
        ]
        let commit = try await SystemProcess.output(
            "/usr/bin/git", options + ["rev-parse", "--verify", "\(revision)^{commit}"],
            workingDirectory: destination, customEnvironment: environment
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard commit == revision else {
            throw ToolError.message("source revision \(revision) is not a commit")
        }
        try await SystemProcess.run(
            "/usr/bin/git", options + ["read-tree", revision],
            workingDirectory: destination, customEnvironment: environment
        )
        try await SystemProcess.run(
            "/usr/bin/git", options + ["checkout-index", "--all", "--force"],
            workingDirectory: destination, customEnvironment: environment
        )

        // .gitmodules and gitlinks come from the pin, not the current native work tree.
        guard (try? await SystemProcess.run(
            "/usr/bin/git", ["cat-file", "-e", "\(revision):.gitmodules"],
            workingDirectory: destination, customEnvironment: environment
        )) != nil else { return }
        let configuration = try await SystemProcess.output(
            "/usr/bin/git", ["config", "--null", "--blob", "\(revision):.gitmodules", "--list"],
            workingDirectory: destination, customEnvironment: environment
        )
        for entry in configuration.split(separator: "\0") {
            guard let separator = entry.firstIndex(of: "\n") else { continue }
            let key = String(entry[..<separator])
            guard key.hasPrefix("submodule."), key.hasSuffix(".path") else { continue }
            let name = String(key.dropFirst("submodule.".count).dropLast(".path".count))
            let path = String(entry[entry.index(after: separator)...])
            let child = destination.appendingPathComponent(path).standardizedFileURL
            let nativeChild = nativeDirectory.appendingPathComponent(path).standardizedFileURL
            guard child.path.hasPrefix(destination.standardizedFileURL.path + "/"),
                  child.resolvingSymlinksInPath().path.hasPrefix(destination.resolvingSymlinksInPath().path + "/"),
                  nativeChild.path.hasPrefix(nativeDirectory.standardizedFileURL.path + "/"),
                  !fileSystem.existsIncludingSymlinks(child) || fileSystem.isDirectoryAndNotSymlink(child)
            else { throw ToolError.message("invalid submodule path \(path)") }
            let tree = try await SystemProcess.output(
                "/usr/bin/git", ["ls-tree", "-z", revision, "--", path],
                workingDirectory: destination, customEnvironment: environment
            )
            guard let metadata = tree.split(separator: "\t").first else { continue }
            let fields = metadata.split(separator: " ")
            guard fields.count == 3, fields[0] == "160000", fields[1] == "commit" else { continue }
            let childGit: URL
            if fileSystem.existsIncludingSymlinks(nativeChild.appendingPathComponent(".git")) {
                childGit = try await URL(fileURLWithPath: SystemProcess.output(
                    "/usr/bin/git", ["-C", nativeChild.path, "rev-parse", "--absolute-git-dir"],
                    customEnvironment: gitEnvironment
                ).trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                let common = try await SystemProcess.output(
                    "/usr/bin/git", ["rev-parse", "--path-format=absolute", "--git-common-dir"],
                    workingDirectory: destination, customEnvironment: environment
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                let modules = URL(fileURLWithPath: common).appendingPathComponent("modules").standardizedFileURL
                childGit = modules.appendingPathComponent(name).standardizedFileURL
                guard childGit.path.hasPrefix(modules.path + "/") else {
                    throw ToolError.message("invalid submodule name \(name)")
                }
                if try await !fileSystem.exists(childGit.absolutePath) {
                    if fileSystem.isDirectoryAndNotSymlink(nativeChild),
                       try await !fileSystem.contentsOfDirectory(at: nativeChild).isEmpty
                    { throw ToolError.message("missing Git objects for initialized submodule \(path)") }
                    if fileSystem.existsIncludingSymlinks(child) { try await fileSystem.removePath(child) }
                    continue
                }
            }
            try await export(
                gitDirectory: childGit, nativeDirectory: nativeChild,
                revision: String(fields[2]), destination: child, staging: staging
            )
        }
    }

    static func writeLocalWorkingCopy(from source: String, origin: String, revision: String, to destination: URL) async throws {
        try await SystemProcess.run(
            "/usr/bin/git", ["clone", "--no-local", "--depth", "1", "--no-checkout", "--", source, destination.path],
            customEnvironment: gitEnvironment
        )
        try await SystemProcess.run(
            "/usr/bin/git", ["-C", destination.path, "remote", "set-url", "origin", origin],
            customEnvironment: gitEnvironment
        )
        try await SystemProcess.run(
            "/usr/bin/git", ["-C", destination.path, "fetch", "--depth", "1", "--", source, revision],
            customEnvironment: gitEnvironment
        )
        let tags = try await SystemProcess.output(
            "/usr/bin/git", ["ls-remote", "--tags", "--", source], customEnvironment: gitEnvironment
        )
        let pinnedTags = Set(tags.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(separator: "\t", maxSplits: 1)
            guard fields.count == 2, fields[0] == revision else { return nil }
            let ref = String(fields[1]).replacingOccurrences(of: "^{}", with: "")
            return "\(ref):\(ref)"
        })
        if !pinnedTags.isEmpty {
            try await SystemProcess.run(
                "/usr/bin/git", ["-C", destination.path, "fetch", "--depth", "1", "--", source] + pinnedTags.sorted(),
                customEnvironment: gitEnvironment
            )
        }
        try await SystemProcess.run(
            "/usr/bin/git", ["-C", destination.path, "checkout", "--detach", revision, "--"],
            customEnvironment: gitEnvironment
        )
        let allowsFileProtocol = try await PackageResolver.localSourceControlPackageLocation(origin) != nil
        try await SystemProcess.run(
            "/usr/bin/git",
            ["-C", destination.path] + (allowsFileProtocol ? ["-c", "protocol.file.allow=always"] : [])
                + ["submodule", "update", "--init", "--recursive"],
            customEnvironment: gitEnvironment
        )
    }

    static func canReplaceOlderCheckout(_ checkout: URL, revision: String) async throws -> Bool {
        let head = try await SystemProcess.output(
            "/usr/bin/git", ["-C", checkout.path, "rev-parse", "HEAD"], customEnvironment: gitEnvironment
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard head != revision, try await isPristine(checkout, revision: head) else { return false }
        let references = try await SystemProcess.output(
            "/usr/bin/git", [
                "-C",
                checkout.path,
                "for-each-ref",
                "--contains",
                head,
                "--format=%(refname)",
                "refs/remotes",
                "refs/tags",
            ],
            customEnvironment: gitEnvironment
        )
        guard !references.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let unpublished = try await SystemProcess.output(
            "/usr/bin/git", ["-C", checkout.path, "rev-list", "--branches", "--not", "--remotes", "--tags"],
            customEnvironment: gitEnvironment
        )
        return unpublished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isPristine(_ checkout: URL, revision: String) async throws -> Bool {
        let head = try await SystemProcess.output(
            "/usr/bin/git", ["-C", checkout.path, "rev-parse", "HEAD"], customEnvironment: gitEnvironment
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard head == revision else { return false }
        let flags = try await SystemProcess.output(
            "/usr/bin/git", ["-C", checkout.path, "ls-files", "-v", "-z"], customEnvironment: gitEnvironment
        )
        guard !flags.split(separator: "\0").contains(where: { entry in
            guard let flag = entry.first else { return false }
            return flag == "S" || flag.isLowercase
        }) else { return false }
        let status = try await SystemProcess.output(
            "/usr/bin/git",
            [
                "-C",
                checkout.path,
                "status",
                "--porcelain=v1",
                "-z",
                "--untracked-files=all",
                "--ignored=traditional",
                "--ignore-submodules=none",
            ],
            customEnvironment: gitEnvironment
        )
        return status.split(separator: "\0").allSatisfy { entry in
            let kind = entry.prefix(2)
            let path = entry.dropFirst(3)
            return (kind == "??" || kind == "!!") && [
                WorkspaceRestorer.sourceRevisionMarkerFilename,
                ".build/.lock",
                ".build/CACHEDIR.TAG",
                ".build/.buildSystem_debug",
                ".build/swifterpm/manifests/package.json",
                ".build/swifterpm/manifests/package.json.envhash",
                ".build/swifterpm/manifests/package.json.inputs.json",
            ].contains(String(path))
        }
    }
}
