import Foundation
import TOMLDecoder

/// Resolves the original package selection before validating any harness or narrowing a command.
enum CargoTestTargets {
    static func read(
        _ context: CargoExecutionContext, arguments: [String], requiresSinglePackage: Bool
    ) async throws -> [CargoTestTarget] {
        guard let metadata = await context.reporting.process.packageMetadata(
            executable: context.executable, arguments: arguments, directory: context.directory, environment: context.environment
        ) else {
            throw CargoTestSelectionError(message: "Could not resolve Cargo test targets.")
        }
        let selected = try selectedMetadata(metadata, arguments: arguments, directory: context.directory.pathString)
        let packages = selected["packages"] as? [[String: Any]] ?? []
        guard !requiresSinglePackage || packages.count == 1 else {
            throw CargoTestSelectionError(
                message: "Cargo sharding and skip quarantine require one selected package to preserve feature unification. Use -p <package> instead of a multi-package selection."
            )
        }
        try validateHarnesses(selected, arguments: arguments)
        return CargoTestTarget.read(selected, arguments: arguments)
    }

    private static func selectedMetadata(
        _ metadata: [String: Any], arguments: [String], directory: String
    ) throws -> [String: Any] {
        let arguments = Array(arguments.prefix(while: { $0 != "--" }))
        let packages = metadata["packages"] as? [[String: Any]] ?? []
        let explicit = CargoTestTarget.selectedPackages(arguments)
        guard explicit.allSatisfy({ name in packages.contains { $0["name"] as? String == name } }) else {
            throw CargoTestSelectionError(message: "Cargo test selection requires exact workspace package names.")
        }
        var names = Set(explicit)
        if arguments.contains("--workspace") || arguments.contains("--all") {
            names = Set(packages.compactMap { $0["name"] as? String })
        } else if names.isEmpty {
            let manifest = optionValues("--manifest-path", arguments: arguments).first
            var location = URL(fileURLWithPath: directory, isDirectory: true)
            if let manifest {
                location = URL(fileURLWithPath: manifest, relativeTo: location).standardizedFileURL.deletingLastPathComponent()
            } else {
                while !FileManager.default.fileExists(atPath: location.appendingPathComponent("Cargo.toml").path),
                      location.path != "/"
                {
                    location.deleteLastPathComponent()
                }
            }
            let path = location.resolvingSymlinksInPath().path
            let root = (metadata["workspace_root"] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            let defaults = Set(metadata["workspace_default_members"] as? [String] ?? [])
            names = Set(packages.compactMap { package in
                guard let name = package["name"] as? String,
                      let manifest = package["manifest_path"] as? String else { return nil }
                let parent = URL(fileURLWithPath: manifest).deletingLastPathComponent().resolvingSymlinksInPath().path
                return path == root ? (defaults.contains(package["id"] as? String ?? "") ? name : nil) :
                    (parent == path ? name : nil)
            })
        }
        names.subtract(optionValues("--exclude", arguments: arguments))
        var result = metadata
        result["packages"] = packages.filter { names.contains($0["name"] as? String ?? "") }
        return result
    }

    private static func optionValues(_ key: String, arguments: [String]) -> [String] {
        arguments.enumerated().compactMap { index, argument in
            if argument == key, index + 1 < arguments.count { return arguments[index + 1] }
            return argument.hasPrefix(key + "=") ? String(argument.dropFirst(key.count + 1)) : nil
        }
    }

    private static func validateHarnesses(_ metadata: [String: Any], arguments: [String]) throws {
        struct Target: Decodable {
            let name: String?
            let harness: Bool?
            let bench: Bool?
        }
        struct Manifest: Decodable {
            let lib: Target?
            let bin: [Target]?
            let test: [Target]?
            let bench: [Target]?
            let example: [Target]?
        }
        let arguments = Array(arguments.prefix(while: { $0 != "--" }))
        let targetNames = ["--bin", "--test", "--example", "--bench"].flatMap { optionValues($0, arguments: arguments) }
        guard !targetNames.contains(where: { $0.contains(where: { "*?[".contains($0) }) }) else {
            throw CargoTestSelectionError(
                message: "Cargo test selection requires exact target names; target patterns are unsupported."
            )
        }
        let explicit = arguments.contains {
            ["--lib", "--doc", "--bins", "--tests", "--examples", "--benches", "--all-targets"].contains($0)
                || ["--bin", "--test", "--example", "--bench"].contains($0.components(separatedBy: "=")[0])
        }
        for package in metadata["packages"] as? [[String: Any]] ?? [] {
            guard let path = package["manifest_path"] as? String else {
                continue
            }
            let manifest = try TOMLDecoder().decode(Manifest.self, from: String(contentsOfFile: path, encoding: .utf8))
            for target in package["targets"] as? [[String: Any]] ?? [] {
                let kinds = target["kind"] as? [String] ?? []
                guard let kind = kinds.first, kind != "custom-build", let name = target["name"] as? String else { continue }
                let library = !Set(kinds).isDisjoint(with: ["lib", "rlib", "dylib", "cdylib", "staticlib", "proc-macro"])
                let settings: [Target] = library ? (manifest.lib.map { [$0] } ?? []) :
                    (kind == "bin" ? manifest.bin : kind == "test" ? manifest.test : kind == "bench" ? manifest.bench : manifest
                        .example) ?? []
                let configuration = settings.first { library || $0.name == name }
                let bench = configuration?.bench ?? (library || kind == "bin" || kind == "bench")
                let selected = arguments.contains("--all-targets") || (library && arguments.contains("--lib"))
                    || (arguments.contains("--benches") && bench)
                    || arguments.contains("--\(kind)s") || optionValues("--\(kind)", arguments: arguments).contains(name)
                    || ((!explicit || arguments.contains("--tests")) && target["test"] as? Bool == true)
                guard selected else { continue }
                if configuration?.harness == false {
                    throw CargoTestSelectionError(
                        message: "Cargo sharding and skip quarantine require standard libtest harnesses; \(path) disables its harness."
                    )
                }
            }
        }
    }
}
