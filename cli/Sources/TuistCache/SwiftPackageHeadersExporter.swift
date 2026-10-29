import FileSystem
import Foundation
import Path
import TuistSupport
import XcodeGraph

public enum SwiftPackageHeadersExportError: LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(reason): return "Cannot export portable Swift package headers: \(reason)"
        }
    }
}

/// Exports source-backed headers after compilation, outside Xcode's per-file build graph.
/// The original relative include hierarchy is retained, including private headers and duplicate
/// basenames. All symlinks in the resulting artifact point inside that artifact.
public struct SwiftPackageHeadersExporter {
    public static let metadataFileName = "tuist-headers.json"

    struct Metadata: Codable {
        static let fileName = SwiftPackageHeadersExporter.metadataFileName
        let publicDirectory: String
        var namespaceDirectory: String? = nil
        var moduleMap: String? = nil
    }

    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func export(target: Target, artifact: AbsolutePath) async throws -> AbsolutePath? {
        guard let headers = target.headers, let layout = headers.sourceLayout else { return nil }
        let isFramework = target.product == .framework || target.product == .staticFramework
        let container = isFramework ? artifact : artifact.parentDirectory.appending(component: "\(target.name)-headers")
        let currentVersion = artifact.appending(components: "Versions", "Current")
        let destination: AbsolutePath
        if isFramework, try await fileSystem.exists(currentVersion, isDirectory: true) {
            destination = try await fileSystem.resolveSymbolicLink(currentVersion)
            guard destination.isDescendant(of: artifact) else {
                throw SwiftPackageHeadersExportError.unsupported("framework version outside its bundle")
            }
        } else {
            destination = isFramework ? container : container.appending(component: layout.moduleName)
        }
        // Xcode strips Headers and PrivateHeaders when embedding a framework. Keep every
        // compilation-only file under those standard directories, including the metadata.
        let support = isFramework ? destination.appending(component: "PrivateHeaders") : destination
        let tree = support.appending(component: "TuistHeaders")
        let publicRelativePath = layout.publicHeaders.relative(to: layout.root)
        guard layout.publicHeaders.isDescendantOfOrEqual(to: layout.root) else {
            throw SwiftPackageHeadersExportError.unsupported("public headers outside \(layout.root)")
        }
        let sourceMap = try await fileSystem.readTextFile(at: layout.moduleMap)
        let relocated = try SwiftPackageModuleMapRelocator.relocate(
            sourceMap, layout: layout, framework: isFramework
        )
        let paths = Set(headers.public + headers.private + headers.project)
        guard relocated.references.allSatisfy(paths.contains) else {
            throw SwiftPackageHeadersExportError.unsupported("module map references a header excluded from discovery")
        }
        for path in paths {
            guard path.isDescendant(of: layout.root) else {
                throw SwiftPackageHeadersExportError.unsupported("header outside target: \(path)")
            }
        }
        // Remove the public alias before its destination, including on repeated exports.
        let namespaceDirectory = support.appending(component: "TuistIncludes")
        let publicLink = isFramework ? destination.appending(component: "Headers")
            : namespaceDirectory.appending(component: layout.moduleName)
        try await removeAlias(at: publicLink)
        if try await fileSystem.exists(tree) { try await fileSystem.remove(tree) }
        try await fileSystem.makeDirectory(at: tree.appending(publicRelativePath))
        let destinations = paths.sorted().map { ($0, tree.appending($0.relative(to: layout.root))) }
        for directory in Set(destinations.map(\.1.parentDirectory)).sorted() {
            try await fileSystem.makeDirectory(at: directory)
        }
        _ = try await destinations.concurrentMap(maxConcurrentTasks: 8) { source, destination in
            // Reading bytes follows package symlinks. Copying the link itself could leave an artifact
            // pointing at the original checkout; FileSystem has no binary write API.
            let contents = try await fileSystem.readFile(at: source)
            try contents.write(to: destination.url)
        }

        if layout.usesDirectoryModuleMap {
            try await fileSystem.makeDirectory(at: publicLink.parentDirectory)
            try await fileSystem.createSymbolicLink(
                from: publicLink,
                to: tree.appending(publicRelativePath).relative(to: publicLink.parentDirectory)
            )
            if isFramework {
                let namespace = namespaceDirectory.appending(component: layout.moduleName)
                try await fileSystem.makeDirectory(at: namespaceDirectory)
                try await removeAlias(at: namespace)
                try await fileSystem.createSymbolicLink(
                    from: namespace, to: tree.appending(publicRelativePath).relative(to: namespaceDirectory)
                )
            }
        } else if isFramework {
            // Framework module-map header paths resolve against this directory. Keep it empty
            // so caching does not flip sibling shims' __has_include(<Module/Header.h>) branches.
            try await fileSystem.makeDirectory(at: publicLink)
        }
        let moduleMap = isFramework
            ? destination.appending(components: "Modules", "module.modulemap")
            : destination.appending(component: "module.modulemap")
        let treeRelative = isFramework ? "PrivateHeaders/TuistHeaders" : tree.relative(to: container).pathString
        try await fileSystem.writeAsJSON(
            Metadata(
                publicDirectory: treeRelative + "/" + publicRelativePath.pathString,
                namespaceDirectory: layout.usesDirectoryModuleMap
                    ? (isFramework ? "PrivateHeaders/TuistIncludes" : namespaceDirectory.relative(to: container).pathString) :
                    nil,
                moduleMap: isFramework ? "Modules/module.modulemap" : moduleMap.relative(to: container).pathString
            ),
            at: support.appending(component: Metadata.fileName)
        )
        try await fileSystem.makeDirectory(at: moduleMap.parentDirectory)
        try await fileSystem.writeText(relocated.contents, at: moduleMap, encoding: .utf8, options: [.overwrite])
        if isFramework, destination != container {
            for component in ["Headers", "PrivateHeaders", "Modules"] {
                let alias = container.appending(component: component)
                try await removeAlias(at: alias)
                try await fileSystem.createSymbolicLink(
                    from: alias, to: try RelativePath(validating: "Versions/Current/\(component)")
                )
            }
        }
        return isFramework ? container.appending(component: "Headers") : container
    }

    private func removeAlias(at path: AbsolutePath) async throws {
        // FileSystem.exists/remove follow symlinks and cannot remove dangling framework aliases.
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: path.pathString)) != nil {
            try FileManager.default.removeItem(at: path.url)
        } else if try await fileSystem.exists(path) {
            try await fileSystem.remove(path)
        }
    }
}
