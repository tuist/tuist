import Foundation

enum ManifestDependencyKind: Hashable, Sendable {
    case sourceControl
    case registry
}

struct ManifestDependency: Sendable {
    let identity: String
    let kind: ManifestDependencyKind
    let location: String
    let requirement: Requirement
    let nameForTargetDependencyResolutionOnly: String?

    init(
        identity: String,
        kind: ManifestDependencyKind,
        location: String,
        requirement: Requirement,
        nameForTargetDependencyResolutionOnly: String? = nil
    ) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.requirement = requirement
        self.nameForTargetDependencyResolutionOnly = nameForTargetDependencyResolutionOnly
    }
}

struct ManifestFileSystemDependency: Sendable {
    let identity: String
    let name: String
    let path: String
}

struct ManifestBinaryTarget: Sendable {
    enum Source: Sendable {
        case local(path: String)
        case remote(url: String, checksum: String)
    }

    let name: String
    let source: Source
}

enum Requirement: Sendable {
    case exact(SemVer)
    case range(lower: SemVer, upper: SemVer)
    case revision(String)
    case branch(String)
}

enum ManifestLoader {
    static let cacheDirectory = ".build/swifterpm/manifests"
    static let cacheFile = "package.json"

    static func cacheFilePath(packageDir: URL) -> URL {
        packageDir
            .appendingPathComponent(cacheDirectory)
            .appendingPathComponent(cacheFile)
    }

    static func dumpPackage(packageDir: URL, disableSandbox: Bool) async throws -> Any {
        let data = try await ManifestLoader.dumpPackageJSON(
            packageDir: packageDir, disableSandbox: disableSandbox
        )
        return try JSONSerialization.jsonObject(with: data)
    }

    static func dumpPackageJSON(packageDir: URL, disableSandbox: Bool) async throws -> Data {
        if let cached = try await readCachedManifest(packageDir: packageDir) {
            return cached
        }

        var args = ["package"]
        if disableSandbox {
            args.append("--disable-sandbox")
        }
        args.append("dump-package")
        let result = try await SystemProcess.run(
            "/usr/bin/swift", args, workingDirectory: packageDir
        )
        try? await fileSystem.atomicWrite(result.stdout, to: cacheFilePath(packageDir: packageDir))
        return result.stdout
    }

    private static func readCachedManifest(packageDir: URL) async throws -> Data? {
        let cache = cacheFilePath(packageDir: packageDir)
        let manifest = packageDir.appendingPathComponent("Package.swift")
        guard try await fileSystem.exists(cache.absolutePath) else { return nil }
        guard let cacheDate = try await fileSystem.fileMetadata(at: cache.absolutePath)?.lastModificationDate,
              let manifestDate = try await fileSystem.fileMetadata(at: manifest.absolutePath)?.lastModificationDate,
              cacheDate >= manifestDate
        else {
            return nil
        }
        return try await fileSystem.readFile(at: cache.absolutePath)
    }
}

struct ManifestFileSystemPackage: @unchecked Sendable {
    let dependency: ManifestFileSystemDependency
    let packagePath: URL
    let manifest: Any
}

enum ManifestFileSystemDependencyGraph {
    static func collect(
        rootPackageDir: URL,
        rootManifest: Any,
        disableSandbox: Bool
    ) async throws -> [ManifestFileSystemPackage] {
        var result: [ManifestFileSystemPackage] = []
        var seenPackagePaths = Set<String>()
        var queue = try ManifestParser.fileSystemDependencies(rootManifest).map {
            (parentPackageDir: rootPackageDir, dependency: $0)
        }

        while !queue.isEmpty {
            let item = queue.removeFirst()
            let packagePath = packagePathForFileSystemDependency(
                parentPackageDir: item.parentPackageDir,
                dependency: item.dependency
            )
            let canonicalPath = PathCanonicalizer.realpath(packagePath)
            guard seenPackagePaths.insert(canonicalPath.path).inserted else {
                continue
            }

            let manifest = try await ManifestLoader.dumpPackage(
                packageDir: canonicalPath,
                disableSandbox: disableSandbox
            )
            result.append(
                ManifestFileSystemPackage(
                    dependency: item.dependency,
                    packagePath: canonicalPath,
                    manifest: manifest
                )
            )
            for child in try ManifestParser.fileSystemDependencies(manifest) {
                queue.append((parentPackageDir: canonicalPath, dependency: child))
            }
        }

        return result
    }

    static func packagePathForFileSystemDependency(
        parentPackageDir: URL,
        dependency: ManifestFileSystemDependency
    ) -> URL {
        if dependency.path.hasPrefix("/") {
            return URL(fileURLWithPath: dependency.path).standardizedFileURL
        }
        return parentPackageDir
            .appendingPathComponent(dependency.path)
            .standardizedFileURL
    }
}

enum ManifestParser {
    static func packageName(_ manifest: Any) -> String? {
        (manifest as? [String: Any])?["name"] as? String
    }

    static func dependencies(_ manifest: Any) throws -> [ManifestDependency] {
        var dependencies: [ManifestDependency] = []
        guard let root = manifest as? [String: Any],
              let items = root["dependencies"] as? [[String: Any]]
        else {
            return dependencies
        }

        for item in items {
            if let sourceControl = item["sourceControl"] as? [[String: Any]] {
                for dependency in sourceControl {
                    guard let identity = dependency["identity"] as? String else {
                        throw ToolError.message("sourceControl dependency is missing identity")
                    }
                    guard let location = parseSourceControlLocation(dependency) else {
                        throw ToolError.message("\(identity) is missing source-control location")
                    }
                    guard let requirementJSON = dependency["requirement"] else {
                        throw ToolError.message("\(identity) is missing requirement")
                    }
                    try dependencies.append(
                        ManifestDependency(
                            identity: identity,
                            kind: .sourceControl,
                            location: location,
                            requirement: requirement(requirementJSON),
                            nameForTargetDependencyResolutionOnly:
                                dependency["nameForTargetDependencyResolutionOnly"] as? String
                        ))
                }
            }

            if let registry = item["registry"] as? [[String: Any]] {
                for dependency in registry {
                    guard let identity = dependency["identity"] as? String else {
                        throw ToolError.message("registry dependency is missing identity")
                    }
                    guard let requirementJSON = dependency["requirement"] else {
                        throw ToolError.message("\(identity) is missing requirement")
                    }
                    try dependencies.append(
                        ManifestDependency(
                            identity: identity,
                            kind: .registry,
                            location: identity,
                            requirement: requirement(requirementJSON)
                        ))
                }
            }
        }

        return dependencies
    }

    private static func parseSourceControlLocation(_ dependency: [String: Any]) -> String? {
        guard let location = dependency["location"] as? [String: Any] else {
            return nil
        }
        if let remote = location["remote"] as? [[String: Any]],
           let first = remote.first,
           let url = first["urlString"] as? String
        {
            return url
        }
        if let local = location["local"] as? [String],
           let first = local.first
        {
            return first
        }
        return nil
    }

    static func requiredDependencies(_ manifest: Any) throws -> [ManifestDependency] {
        let dependencies = try dependencies(manifest)
        let references = activeDependencyReferences(manifest)
        if references.isEmpty {
            return []
        }
        return dependencies.filter { dependency in
            dependencyReferenceNames(dependency).contains { references.contains($0) }
        }
    }

    private static func activeDependencyReferences(_ manifest: Any) -> Set<String> {
        guard let root = manifest as? [String: Any],
              let targets = root["targets"] as? [[String: Any]]
        else {
            return []
        }

        let targetNames = Set(targets.compactMap { $0["name"] as? String })
        var pendingTargets: [String] = []
        if let products = root["products"] as? [[String: Any]] {
            for product in products {
                if let targets = product["targets"] as? [String] {
                    pendingTargets.append(contentsOf: targets)
                }
            }
        }
        var references = Set<String>()
        var visitedTargets = Set<String>()

        while let targetName = pendingTargets.popLast() {
            guard visitedTargets.insert(targetName).inserted,
                  let target = targets.first(where: { $0["name"] as? String == targetName }),
                  let dependencies = target["dependencies"] as? [[String: Any]]
            else {
                continue
            }

            for dependency in dependencies {
                if let product = dependency["product"] as? [Any] {
                    let productName = product.first as? String
                    let packageName = product.count > 1 ? product[1] as? String : nil
                    if let name = packageName ?? productName {
                        references.insert(normalizeDependencyReference(name))
                    }
                }
                if let byName = dependency["byName"] as? [Any],
                   let name = byName.first as? String
                {
                    if targetNames.contains(name) {
                        pendingTargets.append(name)
                    } else {
                        references.insert(normalizeDependencyReference(name))
                    }
                }
                if let target = dependency["target"] as? [Any],
                   let name = target.first as? String,
                   targetNames.contains(name)
                {
                    pendingTargets.append(name)
                }
            }
        }

        return references
    }

    private static func dependencyReferenceNames(_ dependency: ManifestDependency) -> Set<String> {
        var names = Set<String>()
        names.insert(normalizeDependencyReference(dependency.identity))
        if let name = dependency.nameForTargetDependencyResolutionOnly {
            names.insert(normalizeDependencyReference(name))
        }
        if let suffix = dependency.identity.split(separator: ".").last {
            names.insert(normalizeDependencyReference(String(suffix)))
        }
        if dependency.kind == .sourceControl,
           let name = dependency.location.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
           .replacingOccurrences(of: ".git", with: "")
           .split(separator: "/")
           .last
        {
            names.insert(normalizeDependencyReference(String(name)))
        }
        return names
    }

    private static func normalizeDependencyReference(_ name: String) -> String {
        let value = name.hasSuffix(".git") ? String(name.dropLast(4)) : name
        return value.lowercased()
    }

    static func fileSystemDependencies(_ manifest: Any) throws -> [ManifestFileSystemDependency] {
        guard let root = manifest as? [String: Any],
              let items = root["dependencies"] as? [[String: Any]]
        else {
            return []
        }

        var dependencies: [ManifestFileSystemDependency] = []
        for item in items {
            guard let fileSystem = item["fileSystem"] as? [[String: Any]] else { continue }
            for dependency in fileSystem {
                guard let identity = dependency["identity"] as? String else {
                    throw ToolError.message("fileSystem dependency is missing identity")
                }
                guard let path = dependency["path"] as? String else {
                    throw ToolError.message("\(identity) is missing path")
                }
                dependencies.append(
                    ManifestFileSystemDependency(
                        identity: identity,
                        name: dependency["nameForTargetDependencyResolutionOnly"] as? String
                            ?? identity,
                        path: path
                    ))
            }
        }
        return dependencies
    }

    static func binaryTargets(_ manifest: Any) throws -> [ManifestBinaryTarget] {
        guard let root = manifest as? [String: Any],
              let targets = root["targets"] as? [[String: Any]]
        else {
            return []
        }

        var result: [ManifestBinaryTarget] = []
        for target in targets where target["type"] as? String == "binary" {
            guard let name = target["name"] as? String else {
                throw ToolError.message("binary target is missing name")
            }
            if let url = target["url"] as? String {
                guard let checksum = target["checksum"] as? String else {
                    throw ToolError.message("\(name) is missing checksum")
                }
                result.append(
                    ManifestBinaryTarget(name: name, source: .remote(url: url, checksum: checksum))
                )
            } else if let path = target["path"] as? String {
                result.append(ManifestBinaryTarget(name: name, source: .local(path: path)))
            } else {
                throw ToolError.message("\(name) is missing binary artifact path or URL")
            }
        }
        return result
    }

    static func requirement(_ requirement: Any) throws -> Requirement {
        guard let requirement = requirement as? [String: Any] else {
            throw ToolError.message("unsupported requirement shape: \(requirement)")
        }
        if let exact = requirement["exact"] as? [String], let value = exact.first {
            return try .exact(SemVer(value))
        }
        if let range = requirement["range"] as? [[String: Any]], let first = range.first {
            guard let lower = first["lowerBound"] as? String,
                  let upper = first["upperBound"] as? String
            else {
                throw ToolError.message("range is missing lowerBound or upperBound")
            }
            return try .range(lower: SemVer(lower), upper: SemVer(upper))
        }
        if let revision = requirement["revision"] as? [String], let value = revision.first {
            return .revision(value)
        }
        if let branch = requirement["branch"] as? [String], let value = branch.first {
            return .branch(value)
        }
        throw ToolError.message("unsupported requirement shape: \(requirement)")
    }

    static func versionRange(for requirement: Requirement) -> VersionRange? {
        switch requirement {
        case let .exact(version):
            return .singleton(version)
        case let .range(lower, upper):
            return .between(lower, upper)
        case .revision, .branch:
            return nil
        }
    }
}
