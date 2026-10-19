import Foundation

/// SwiftPM records prebuilts such as swift-syntax `MacroSupport` in `workspace-state.json`, extracted to
/// `<scratch>/prebuilts/<identity>/<version>/<name>-<library>`, where `<name>` is `<compiler tag>-<platform>` for the
/// toolchain it resolved with. It recomputes them on every resolution. The restoration path carries the recorded
/// entries over instead, so it must drop the ones SwiftPM would no longer produce: modules built by another compiler
/// or against another SDK cannot be imported (they ship without interfaces), a prebuilt for another version does not
/// match the restored sources, and an entry whose directory is gone points the build at nothing. The entries it keeps
/// are rebased onto the current scratch directory, since SwiftPM records absolute paths.
///
/// A dropped entry is not replaced. The restoration path cannot fetch prebuilts, so those packages build from source
/// until a native resolution records them again, as they do in a fresh scratch directory.
enum WorkspacePrebuilts {
    /// Tests replace the probe to simulate a toolchain change without launching `swift`.
    @TaskLocal static var nameProbe: @Sendable (_ packageDir: URL) async throws -> String? = {
        try await probeName(packageDir: $0)
    }

    /// `name` probes the toolchain (`nameProbe`); it is only called when there is something to check, since most
    /// graphs record no prebuilts.
    static func carriedOver(
        _ recorded: [[String: Any]],
        pins: [ResolvedPin],
        scratchDir: URL,
        name: () async throws -> String?
    ) async throws -> [[String: Any]] {
        guard !recorded.isEmpty else { return [] }
        let name = try await name()
        if name == nil {
            // Dropping them instead would discard valid prebuilts on every restore.
            Environment.warningHandler?(
                "could not determine which prebuilts the current toolchain uses; keeping the recorded ones unchecked"
            )
        }
        var carriedOver: [[String: Any]] = []
        var dropped: [String] = []
        for prebuilt in recorded {
            if let applicable = try await applicable(prebuilt, pins: pins, scratchDir: scratchDir, name: name) {
                carriedOver.append(applicable)
            } else {
                dropped.append(
                    ["identity", "version", "libraryName"].compactMap { prebuilt[$0] as? String }.joined(separator: " ")
                )
            }
        }
        if !dropped.isEmpty {
            Environment.warningHandler?(
                "dropped recorded prebuilts that the current toolchain or pins cannot use, so their packages build from "
                    + "source until a native resolution records new ones: \(dropped.joined(separator: ", "))"
            )
        }
        return carriedOver
    }

    /// The entry rebased onto `scratchDir`, or `nil` when SwiftPM would not produce it.
    static func applicable(
        _ prebuilt: [String: Any],
        pins: [ResolvedPin],
        scratchDir: URL,
        name: String?
    ) async throws -> [String: Any]? {
        guard let identity = prebuilt["identity"] as? String,
              let version = prebuilt["version"] as? String,
              let library = prebuilt["libraryName"] as? String,
              let path = prebuilt["path"] as? String,
              pins.contains(where: { $0.identity.lowercased() == identity.lowercased() && $0.state.version == version })
        else { return nil }
        let directoryName = URL(fileURLWithPath: path).lastPathComponent
        // The whole name, not a prefix: a tag can be the start of another one (snapshot toolchains), and the same
        // compiler can have prebuilts for several SDKs.
        if let name, directoryName != "\(name)-\(library)" { return nil }
        // A scratch directory restored to another location, from a CI cache for example, records the old one.
        let extracted = scratchDir.appendingPathComponent("prebuilts")
            .appendingPathComponent(identity)
            .appendingPathComponent(version)
            .appendingPathComponent(directoryName)
        // `.build/prebuilts` can be cleared, or left out of a CI cache, while the workspace state survives.
        guard try await fileSystem.exists(extracted.absolutePath) else { return nil }
        var rebased = prebuilt
        rebased["path"] = extracted.path
        rebased["checkoutPath"] = scratchDir.appendingPathComponent("checkouts").appendingPathComponent(identity).path
        return rebased
    }

    /// `<compiler tag>-<platform>`, the name SwiftPM gives the prebuilts of the toolchain that native resolution
    /// runs with (`PrebuiltsManager.prebuiltName`), or `nil` when either part cannot be determined.
    static func probeName(packageDir: URL) async throws -> String? {
        guard let compilerTag = try await probeCompilerTag(packageDir: packageDir),
              let platform = try await probePlatformName(compilerTag: compilerTag)
        else { return nil }
        return "\(compilerTag)-\(platform)"
    }

    /// Runs the compiler the way native resolution finds it: SwiftPM prefers `SWIFT_EXEC`, and a toolchain selected
    /// per package (for example through swiftly's `.swift-version`) needs the package directory. `SwifterPM.restore`
    /// takes no resolution environment, so it probes with the process environment, which is all it has.
    static func probeCompilerTag(packageDir: URL) async throws -> String? {
        let environment = Environment.resolution ?? Environment.current
        let output: String
        do {
            output = try await SystemProcess.run(
                environment["SWIFT_EXEC"] ?? "swift",
                ["-print-target-info"],
                workingDirectory: packageDir,
                customEnvironment: Environment.resolution
            ).stdoutString
        } catch {
            try Task.checkCancellation()
            return nil
        }
        guard let targetInfo = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else {
            return nil
        }
        return compilerTag(targetInfo: targetInfo)
    }

    /// Matches SwiftPM's `UserToolchain.computeSwiftCompilerVersion`.
    static func compilerTag(targetInfo: [String: Any]) -> String? {
        if let swiftCompilerTag = targetInfo["swiftCompilerTag"] as? String {
            return swiftCompilerTag
        }
        guard let compilerVersion = targetInfo["compilerVersion"] as? String else { return nil }
        if let match = try? Regex(#"\((swift(lang)?-[^ )]*)"#).firstMatch(in: compilerVersion),
           let tag = match[1].substring
        {
            return String(tag)
        }
        if let match = try? Regex(#"\(.*Swift (.*)[ )]"#).firstMatch(in: compilerVersion),
           let version = match[1].substring
        {
            return "swift-\(version)"
        }
        return nil
    }

    /// SwiftPM names the prebuilts of an Xcode toolchain after the macOS SDK it uses, and the others after the host
    /// platform (`PrebuiltsPlatform.hostPlatform`).
    static func probePlatformName(compilerTag: String) async throws -> String? {
        #if os(macOS)
            guard compilerTag.hasPrefix("swiftlang-") else { return "macos_universal" }
            return try await macOSSDKCanonicalName()
        #elseif os(Linux)
            #if arch(arm64)
                let arch = "aarch64"
            #else
                let arch = "x86_64"
            #endif
            guard let osRelease = try? await fileSystem.readTextFile(at: URL(fileURLWithPath: "/etc/os-release").absolutePath)
            else { return nil }
            return linuxPlatformName(osRelease: osRelease, arch: arch)
        #else
            return nil
        #endif
    }

    /// The SDK SwiftPM's host toolchain uses: `SDKROOT`, then `SWIFTPM_SDKROOT_macosx`, then `xcrun`.
    private static func macOSSDKCanonicalName() async throws -> String? {
        let environment = Environment.resolution ?? Environment.current
        let sdkPath: String
        if let sdkRoot = environment["SDKROOT"] ?? environment["SWIFTPM_SDKROOT_macosx"] {
            sdkPath = sdkRoot
        } else {
            do {
                sdkPath = try await SystemProcess.run(
                    "/usr/bin/xcrun",
                    ["--sdk", "macosx", "--show-sdk-path"],
                    customEnvironment: Environment.resolution
                ).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                try Task.checkCancellation()
                return nil
            }
        }
        let settings = URL(fileURLWithPath: sdkPath).appendingPathComponent("SDKSettings.json")
        guard let data = try? await fileSystem.readFile(at: settings.absolutePath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["CanonicalName"] as? String
    }

    /// Matches the Linux distributions `PrebuiltsPlatform.hostPlatform` has prebuilts for.
    static func linuxPlatformName(osRelease: String, arch: String) -> String? {
        let fields = osRelease.split(separator: "\n").reduce(into: [String: String]()) { fields, line in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return }
            fields[String(parts[0])] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        let version = fields["VERSION_ID"]
        let distribution: String? = switch fields["ID"] {
        case "ubuntu":
            fields["VERSION_CODENAME"].flatMap { ["noble", "jammy", "focal"].contains($0) ? "ubuntu_\($0)" : nil }
        case "fedora":
            ["39", "41"].contains(version ?? "") ? "fedora_39" : nil
        case "amzn":
            version == "2" ? "amazonlinux2" : nil
        case "rhel":
            version?.split(separator: ".").first == "9" ? "rhel_ubi9" : nil
        case "debian":
            version == "12" ? "debian_12" : nil
        default:
            nil
        }
        return distribution.map { "\($0)_\(arch)" }
    }
}

extension SwifterPM {
    /// Whether restoring the package would drop prebuilts that the `workspace-state.json` in `scratchDirectory`
    /// records: built by another toolchain, for another pinned version, or no longer extracted. Projects generated
    /// from that state link prebuilts the compiler cannot import, so callers can ask for a restore first.
    public func recordsOutdatedPrebuilts(packageDirectory: URL, scratchDirectory: URL) async throws -> Bool {
        let recorded = try await WorkspaceRestorer.existingWorkspacePrebuilts(scratchDir: scratchDirectory)
        guard !recorded.isEmpty,
              try await fileSystem.exists(packageDirectory.appendingPathComponent("Package.resolved").absolutePath)
        else { return false }
        let pins = try await ResolvedFile.read(packageDir: packageDirectory).pins
        // The restore warns about dropped or unchecked prebuilts when it runs; here they only answer the question.
        let carriedOver = try await Environment.$warningHandler.withValue(nil) {
            try await WorkspacePrebuilts.carriedOver(recorded, pins: pins, scratchDir: scratchDirectory) {
                try await WorkspacePrebuilts.nameProbe(packageDirectory)
            }
        }
        return carriedOver.count != recorded.count
    }
}
