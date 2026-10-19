import Foundation

/// SwiftPM records prebuilts such as swift-syntax `MacroSupport` in `workspace-state.json` for the
/// compiler and package version it resolved with, and recomputes them on every resolution. Warm
/// restores reuse the recorded entries instead, so they must drop the ones SwiftPM would no longer
/// produce: modules built by another compiler cannot be imported (they ship without interfaces), and
/// a prebuilt for another version does not match the checked-out sources.
enum WorkspacePrebuilts {
    /// The compiler native resolution runs with, probed at most once per invocation, including
    /// failures. `ManifestCache.withContext` installs a fresh one; tests pass a fixed probe.
    actor CompilerTag {
        private let probe: @Sendable () async -> String?
        private var result: Task<String?, Never>?

        init(probe: @escaping @Sendable () async -> String? = WorkspacePrebuilts.probeCompilerTag) {
            self.probe = probe
        }

        func value() async -> String? {
            if let result { return await result.value }
            let result = Task {
                await probe()
            }
            self.result = result
            return await result.value
        }
    }

    @TaskLocal static var compilerTag = CompilerTag()

    static func existing(scratchDir: URL) async throws -> [[String: Any]] {
        let statePath = scratchDir.appendingPathComponent("workspace-state.json")
        guard try await fileSystem.exists(statePath.absolutePath) else { return [] }

        let state = try JSONSerialization.jsonObject(
            with: await fileSystem.readFile(at: statePath.absolutePath)
        ) as? [String: Any]
        let object = state?["object"] as? [String: Any]

        return object?["prebuilts"] as? [[String: Any]] ?? []
    }

    static func applicable(_ prebuilts: [[String: Any]], pins: [ResolvedPin]) async -> [[String: Any]] {
        // Only probe the compiler when there is something to check; most graphs have no prebuilts.
        guard !prebuilts.isEmpty else { return [] }
        let compilerTag = await compilerTag.value()
        return prebuilts.filter { isApplicable($0, pins: pins, compilerTag: compilerTag) }
    }

    static func hasInapplicable(scratchDir: URL, pins: [ResolvedPin]) async throws -> Bool {
        let prebuilts = try await existing(scratchDir: scratchDir)
        return await applicable(prebuilts, pins: pins).count != prebuilts.count
    }

    static func isApplicable(_ prebuilt: [String: Any], pins: [ResolvedPin], compilerTag: String?) -> Bool {
        guard let compilerTag,
              let identity = prebuilt["identity"] as? String,
              let version = prebuilt["version"] as? String,
              let path = prebuilt["path"] as? String
        else { return false }
        // SwiftPM names the extracted directory `<compiler tag>-<platform>-<library>`.
        guard URL(fileURLWithPath: path).lastPathComponent.hasPrefix("\(compilerTag)-") else { return false }
        return pins.contains { $0.identity.lowercased() == identity.lowercased() && $0.state.version == version }
    }

    static func probeCompilerTag() async -> String? {
        guard let output = try? await SystemProcess.run(
            "swift", ["-print-target-info"], customEnvironment: Environment.resolution
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
