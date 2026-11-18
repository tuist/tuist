import Foundation
import TOMLDecoder

struct CargoConfiguration: Decodable {
    struct Build: Decodable {
        var rustcWrapper: String?
        enum CodingKeys: String, CodingKey { case rustcWrapper = "rustc-wrapper" }
    }

    var build: Build?

    private static func configurationDirectories(directory: URL, environment: [String: String]) -> [URL] {
        var paths: [URL] = []
        var current = directory
        while true {
            paths.insert(current.appendingPathComponent(".cargo"), at: 0)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        let home = URL(fileURLWithPath: environment["CARGO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cargo").path)
        return [home] + paths
    }

    private struct Runners: Decodable {
        struct Target: Decodable {
            struct Present: Decodable {
                init(from _: Decoder) throws {}
            }

            let runner: Present?
        }

        let target: [String: Target]?
    }

    /// Whether a Cargo configuration file, or a `--config` option, sets a target runner (`target.<triple>.runner`
    /// or `target.'cfg(…)'.runner`). Code coverage records test processes through a runner of its own, which an
    /// environment runner it can chain to, but a configured one would be replaced by. A file that cannot be read
    /// counts as setting one.
    static func definesRunner(directory: URL, arguments: [String], environment: [String: String]) -> Bool {
        func defines(_ text: String) -> Bool {
            guard let runners = try? TOMLDecoder().decode(Runners.self, from: text) else { return true }
            return runners.target?.values.contains { $0.runner != nil } ?? false
        }
        for path in configurationDirectories(directory: directory, environment: environment) {
            let legacy = path.appendingPathComponent("config")
            let file = FileManager.default.fileExists(atPath: legacy.path) ? legacy : path.appendingPathComponent("config.toml")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8), !defines(text) else { return true }
        }
        let options = Array(arguments.prefix { $0 != "--" })
        for (index, option) in options.enumerated() {
            let value = option == "--config" && index + 1 < options.count ? options[index + 1]
                : option.hasPrefix("--config=") ? String(option.dropFirst(9)) : nil
            guard let value else { continue }
            if value.contains("=") {
                if value.contains("runner") { return true }
            } else if let text = try? String(contentsOf: URL(fileURLWithPath: value, relativeTo: directory), encoding: .utf8) {
                if defines(text) { return true }
            } else {
                return true
            }
        }
        return false
    }

    private struct Target: Decodable {
        struct Build: Decodable { let target: String? }
        let build: Build?
    }

    /// `build.target` of the nearest configuration file that sets one to a single triple, which places a build's
    /// profiles under `target/<triple>`.
    static func buildTarget(directory: URL, environment: [String: String]) -> String? {
        configurationDirectories(directory: directory, environment: environment).reversed().lazy.compactMap { path in
            let legacy = path.appendingPathComponent("config")
            let file = FileManager.default.fileExists(atPath: legacy.path) ? legacy : path.appendingPathComponent("config.toml")
            return (try? String(contentsOf: file, encoding: .utf8))
                .flatMap { try? TOMLDecoder().decode(Target.self, from: $0) }?.build?.target
        }.first
    }

    /// Resolve the compiler wrapper before installing an invocation-local observer.
    /// Cargo's configuration paths are relative to the directory containing .cargo.
    static func compilerWrapper(directory: URL, arguments: [String], environment: [String: String]) throws -> String? {
        if let wrapper = environment["RUSTC_WRAPPER"] ?? environment["CARGO_BUILD_RUSTC_WRAPPER"] {
            guard !wrapper.isEmpty else { return nil }
            return wrapper.contains("/") && !wrapper.hasPrefix("/") ? directory.appendingPathComponent(wrapper)
                .standardizedFileURL.path : wrapper
        }
        let paths = configurationDirectories(directory: directory, environment: environment)
        var wrapper: String?
        func apply(_ text: String, base: URL) throws {
            if let value = try TOMLDecoder().decode(CargoConfiguration.self, from: text).build?.rustcWrapper {
                if value.isEmpty {
                    wrapper = nil
                } else if value.contains("/"), !value.hasPrefix("/") {
                    wrapper = base.appendingPathComponent(value).standardizedFileURL.path
                } else {
                    wrapper = value
                }
            }
        }
        for path in paths {
            let legacy = path.appendingPathComponent("config")
            let file = FileManager.default.fileExists(atPath: legacy.path) ? legacy : path.appendingPathComponent("config.toml")
            if FileManager.default.fileExists(atPath: file.path) {
                try apply(String(contentsOf: file, encoding: .utf8), base: path.deletingLastPathComponent())
            }
        }
        let beforeSeparator = Array(arguments.prefix { $0 != "--" })
        for (index, option) in beforeSeparator.enumerated() {
            let value: String?
            if option == "--config", index + 1 < beforeSeparator.count {
                value = beforeSeparator[index + 1]
            } else if option.hasPrefix("--config=") {
                value = String(option.dropFirst(9))
            } else {
                value = nil
            }
            if let value {
                if value.contains("=") {
                    try apply(value, base: directory)
                } else {
                    let file = URL(fileURLWithPath: value, relativeTo: directory).standardizedFileURL
                    try apply(
                        String(contentsOf: file, encoding: .utf8),
                        base: file.deletingLastPathComponent().deletingLastPathComponent()
                    )
                }
            }
        }
        return wrapper
    }
}

struct NextestConfiguration: Decodable {
    struct Profile: Decodable {
        struct JUnit: Decodable { let path: String? }
        let junit: JUnit?
    }

    let profile: [String: Profile]?

    static func junitPath(
        workspace: URL,
        target: URL,
        directory: URL? = nil,
        arguments: [String],
        environment: [String: String],
        fallback: URL
    ) throws -> URL {
        var profile = environment["NEXTEST_PROFILE"] ?? "default"
        var config = workspace.appendingPathComponent(".config/nextest.toml")
        for (index, option) in arguments.prefix(while: { $0 != "--" }).enumerated() {
            if option == "--profile" || option == "-P", index + 1 < arguments.count { profile = arguments[index + 1] }
            if option == "--config-file", index + 1 < arguments.count { config = URL(
                fileURLWithPath: arguments[index + 1],
                relativeTo: directory ?? workspace
            ).standardizedFileURL }
            if option.hasPrefix("--profile=") { profile = String(option.dropFirst(10)) }
            if option.hasPrefix("-P"), option.count > 2 { profile = String(option.dropFirst(2)) }
            if option.hasPrefix("--config-file=") { config = URL(
                fileURLWithPath: String(option.dropFirst(14)),
                relativeTo: directory ?? workspace
            ).standardizedFileURL }
        }
        guard FileManager.default.fileExists(atPath: config.path) else { return fallback }
        let decoded = try TOMLDecoder().decode(NextestConfiguration.self, from: String(contentsOf: config, encoding: .utf8))
        guard let path = decoded.profile?[profile]?.junit?.path ?? decoded.profile?["default"]?.junit?.path
        else { return fallback }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return target.appendingPathComponent("nextest").appendingPathComponent(profile).appendingPathComponent(path)
    }
}
