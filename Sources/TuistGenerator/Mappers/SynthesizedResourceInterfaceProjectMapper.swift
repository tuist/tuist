import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// A project mapper that synthezies resource interfaces
public final class SynthesizedResourceInterfaceProjectMapper: ProjectMapping {
    private let synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating
    private let contentHasher: ContentHashing

    public convenience init(contentHasher: ContentHashing) {
        self.init(
            synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerator(),
            contentHasher: contentHasher
        )
    }

    init(
        synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating,
        contentHasher: ContentHashing
    ) {
        self.synthesizedResourceInterfacesGenerator = synthesizedResourceInterfacesGenerator
        self.contentHasher = contentHasher
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        let mappings = try project.targets
            .map { try mapTarget($0, project: project) }

        let targets: [Target] = mappings.map(\.0)
        let sideEffects: [SideEffectDescriptor] = mappings.map(\.1).flatMap { $0 }

        return (project.with(targets: targets), sideEffects)
    }

    // MARK: - Helpers

    private struct RenderedFile: Hashable {
        let path: AbsolutePath
        let contents: Data?
    }

    /// Map and generate resource interfaces for a given `Target` and `Project`
    private func mapTarget(_ target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        guard !target.resources.isEmpty, target.supportsSources else { return (target, []) }

        var target = target

        var sideEffects: [SideEffectDescriptor] = []

        let assetsSideEffects: [SideEffectDescriptor]
        (target, assetsSideEffects) = try renderAndMapTarget(
            .assets,
            target: target,
            project: project
        )
        sideEffects += assetsSideEffects

        let stringsSideEffects: [SideEffectDescriptor]
        (target, stringsSideEffects) = try renderAndMapTarget(
            .strings,
            target: target,
            project: project
        )
        sideEffects += stringsSideEffects

        let plistsSideEffects: [SideEffectDescriptor]
        (target, plistsSideEffects) = try renderAndMapTarget(
            .plists,
            target: target,
            project: project
        )
        sideEffects += plistsSideEffects

        let fontsSideEffects: [SideEffectDescriptor]
        (target, fontsSideEffects) = try renderAndMapTarget(
            .fonts,
            target: target,
            project: project
        )
        sideEffects += fontsSideEffects

        return (target, sideEffects)
    }

    /// - Returns: Modified `Target`, side effects, input paths and output paths which can then be later used in generate script
    private func renderAndMapTarget(
        _ synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        target: Target,
        project: Project
    ) throws -> (
        target: Target,
        sideEffects: [SideEffectDescriptor]
    ) {
        let derivedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)

        let paths = try self.paths(for: synthesizedResourceInterfaceType, target: target)
            .filter(isResourceEmpty)

        let renderedInterfaces: [(String, String)]

        switch synthesizedResourceInterfaceType {
        case .plists:
            renderedInterfaces = try paths.map { path in
                let name = self.name(
                    for: synthesizedResourceInterfaceType,
                    path: path,
                    target: target
                )
                return (
                    name,
                    try synthesizedResourceInterfacesGenerator.render(
                        synthesizedResourceInterfaceType,
                        name: name,
                        paths: [path]
                    )
                )
            }
        case .assets, .fonts, .strings:
            if paths.isEmpty {
                renderedInterfaces = []
                break
            }
            let name = self.name(
                for: synthesizedResourceInterfaceType,
                path: project.path,
                target: target
            )
            renderedInterfaces = [
                (
                    synthesizedResourceInterfaceType.name + "+" + name,
                    try synthesizedResourceInterfacesGenerator.render(
                        synthesizedResourceInterfaceType,
                        name: name,
                        paths: paths
                    )
                ),
            ]
        }

        let renderedResources = Set(
            renderedInterfaces.map { name, contents in
                RenderedFile(
                    path: derivedPath.appending(component: name + ".swift"),
                    contents: contents.data(using: .utf8)
                )
            }
        )

        var target = target

        target.sources += try renderedResources
            .map { resource in
                let hash = try resource.contents.map(contentHasher.hash)
                return SourceFile(path: resource.path, contentHash: hash)
            }

        let sideEffects = renderedResources
            .map { FileDescriptor(path: $0.path, contents: $0.contents) }
            .map(SideEffectDescriptor.file)

        return (
            target: target,
            sideEffects: sideEffects
        )
    }

    private func name(
        for synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        path: AbsolutePath,
        target: Target
    ) -> String {
        switch synthesizedResourceInterfaceType {
        case .assets, .strings, .fonts:
            return target.name.camelized.uppercasingFirst
        case .plists:
            return path.basenameWithoutExt.camelized.uppercasingFirst
        }
    }

    private func paths(
        for synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        target: Target
    ) -> [AbsolutePath] {
        let resourcesPaths = target.resources
            .map(\.path)
        switch synthesizedResourceInterfaceType {
        case .assets:
            return resourcesPaths
                .filter { $0.extension == "xcassets" }
        case .strings:
            var seen: Set<String> = []
            return resourcesPaths
                .filter { $0.extension == "strings" || $0.extension == "stringsdict" }
                .filter { seen.insert($0.basename).inserted }
        case .plists:
            return resourcesPaths
                .filter { $0.extension == "plist" }
        case .fonts:
            let fontExtensions = ["otf", "ttc", "ttf"]
            return resourcesPaths
                .filter { $0.extension.map(fontExtensions.contains) ?? false }
        }
    }

    private func isResourceEmpty(_ path: AbsolutePath) throws -> Bool {
        if FileHandler.shared.isFolder(path) {
            if try !FileHandler.shared.contentsOfDirectory(path).isEmpty { return true }
        } else {
            if try !FileHandler.shared.readFile(path).isEmpty { return true }
        }
        logger.log(
            level: .warning,
            "Skipping synthesizing accessors for \(path.pathString) because its contents are empty."
        )
        return false
    }
}
