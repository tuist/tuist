import Foundation

/// SwiftPM records prebuilts such as swift-syntax `MacroSupport` in `workspace-state.json` for the
/// compiler and package version it resolved with, and recomputes them on every resolution. The
/// restoration path carries the recorded entries over instead, so it must drop the ones SwiftPM would
/// no longer produce: modules built by another compiler cannot be imported (they ship without
/// interfaces), and a prebuilt for another version does not match the restored sources.
///
/// A dropped entry is not replaced. The restoration path cannot fetch prebuilts, so those packages
/// build from source until a native resolution records them again, as they do in a fresh scratch
/// directory.
enum WorkspacePrebuilts {
    /// Tests replace the probe to simulate a toolchain change without launching `swift`.
    @TaskLocal static var compilerTagProbe: @Sendable (_ packageDir: URL) async -> String? = {
        await probeCompilerTag(packageDir: $0)
    }

    static func applicable(
        _ prebuilts: [[String: Any]],
        pins: [ResolvedPin],
        packageDir: URL
    ) async -> [[String: Any]] {
        // Most graphs record no prebuilts; only launch the compiler when there is something to check.
        guard !prebuilts.isEmpty else { return [] }
        let compilerTag = await compilerTagProbe(packageDir)
        return prebuilts.filter { isApplicable($0, pins: pins, compilerTag: compilerTag) }
    }

    static func isApplicable(_ prebuilt: [String: Any], pins: [ResolvedPin], compilerTag: String?) -> Bool {
        if let identity = prebuilt["identity"] as? String, let version = prebuilt["version"] as? String,
           !pins.contains(where: { $0.identity.lowercased() == identity.lowercased() && $0.state.version == version })
        {
            return false
        }
        // SwiftPM names the extracted directory `<compiler tag>-<platform>-<library>`. A failed probe
        // says nothing about the prebuilt; treating it as a mismatch would drop valid prebuilts on
        // every restore.
        if let compilerTag, let path = prebuilt["path"] as? String,
           !URL(fileURLWithPath: path).lastPathComponent.hasPrefix("\(compilerTag)-")
        {
            return false
        }
        return true
    }

    /// Runs `swift` the way native resolution does, so a toolchain selected per package (for example
    /// through swiftly's `.swift-version`) yields the tag of the prebuilts that resolution records.
    static func probeCompilerTag(packageDir: URL) async -> String? {
        guard let output = try? await SystemProcess.run(
            "swift",
            ["-print-target-info"],
            workingDirectory: packageDir,
            customEnvironment: Environment.resolution
        ).stdoutString,
            let targetInfo = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        else { return nil }
        return compilerTag(targetInfo: targetInfo)
    }

    /// Matches SwiftPM's `UserToolchain.computeSwiftCompilerVersion`, which names the prebuilts.
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
}
