import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import SwiftGenKit

/// A project mapper that synthesizes resource interfaces
public final class SynthesizedResourceInterfaceProjectMapper: ProjectMapping { // swiftlint:disable:this type_name
    private let synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating
    private let contentHasher: ContentHashing
    private let plugins: Plugins

    public convenience init(
        contentHasher: ContentHashing,
        plugins: Plugins
    ) {
        self.init(
            synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerator(),
            contentHasher: contentHasher,
            plugins: plugins
        )
    }

    init(
        synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating,
        contentHasher: ContentHashing,
        plugins: Plugins
    ) {
        self.synthesizedResourceInterfacesGenerator = synthesizedResourceInterfacesGenerator
        self.contentHasher = contentHasher
        self.plugins = plugins
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
        
        try project.resourceSynthesizers
            .map { resourceSynthesizer throws -> (ResourceSynthesizer, String) in
                if let pluginName = resourceSynthesizer.pluginName {
                    guard let plugin = plugins.resourceSynthesizers.first(where: { $0.name == pluginName }) else { fatalError() }
                    let templateString = try FileHandler.shared.readTextFile(
                        plugin.path
                            .appending(components: "\(resourceSynthesizer.templateName).stencil")
                    )
                    return (resourceSynthesizer, templateString)
                } else {
                    return (resourceSynthesizer, templateString(for: resourceSynthesizer.parser))
                }
            }
            .forEach { parser, templateString in
                let interfaceTypeEffects: [SideEffectDescriptor]
                (target, interfaceTypeEffects) = try renderAndMapTarget(
                    parser,
                    templateString: templateString,
                    target: target,
                    project: project
                )
                sideEffects += interfaceTypeEffects
            }

        return (target, sideEffects)
    }

    /// - Returns: Modified `Target`, side effects, input paths and output paths which can then be later used in generate script
    // swiftlint:disable:next function_body_length
    private func renderAndMapTarget(
        _ resourceSynthesizer: ResourceSynthesizer,
        templateString: String,
        target: Target,
        project: Project
    ) throws -> (
        target: Target,
        sideEffects: [SideEffectDescriptor]
    ) {
        let derivedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)

        let paths = try self.paths(for: resourceSynthesizer, target: target)
            .filter(isResourceEmpty)

        let renderedInterfaces: [(String, String)]

        switch resourceSynthesizer.parser {
        case .plists:
            renderedInterfaces = try paths.map { path in
                let name = self.name(
                    for: resourceSynthesizer,
                    path: path,
                    target: target
                )
                return (
                    name,
                    try synthesizedResourceInterfacesGenerator.render(
                        parser: resourceSynthesizer.parser,
                        templateString: templateString,
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
                for: resourceSynthesizer,
                path: project.path,
                target: target
            )
            renderedInterfaces = [
                (
                    resourceSynthesizer.templateName + "+" + name,
                    try synthesizedResourceInterfacesGenerator.render(
                        parser: resourceSynthesizer.parser,
                        templateString: templateString,
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
        for resourceSynthesizer: ResourceSynthesizer,
        path: AbsolutePath,
        target: Target
    ) -> String {
        switch resourceSynthesizer.parser {
        case .assets, .strings, .fonts:
            return target.name.camelized.uppercasingFirst
        case .plists:
            return path.basenameWithoutExt.camelized.uppercasingFirst
        }
    }

    private func paths(
        for resourceSynthesizer: ResourceSynthesizer,
        target: Target
    ) -> [AbsolutePath] {
        let resourcesPaths = target.resources
            .map(\.path)
        
        var seen: Set<String> = []
        return resourcesPaths
            .filter { $0.extension.map(resourceSynthesizer.extensions.contains) ?? false }
            .filter { seen.insert($0.basename).inserted }
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

    private func templateString(for parser: ResourceSynthesizer.Parser) -> String {
        switch parser {
        case .assets:
            return SynthesizedResourceInterfaceTemplates.assetsTemplate
        case .strings:
            return SynthesizedResourceInterfaceTemplates.stringsTemplate
        case .plists:
            return SynthesizedResourceInterfaceTemplates.plistsTemplate
        case .fonts:
            return SynthesizedResourceInterfaceTemplates.fontsTemplate
        }
    }
}
