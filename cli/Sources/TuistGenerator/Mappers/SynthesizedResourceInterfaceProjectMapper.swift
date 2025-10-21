import Foundation
import Path
import SwiftGenKit
import TuistCore
import TuistSupport
import XcodeGraph

// swiftlint:disable:next type_name
enum SynthesizedResourceInterfaceProjectMapperError: FatalError, Equatable {
    case defaultTemplateNotAvailable(ResourceSynthesizer.Parser)

    var type: ErrorType {
        switch self {
        case .defaultTemplateNotAvailable:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .defaultTemplateNotAvailable(parser):
            return "Default template for parser \(parser) not available."
        }
    }
}

/// A project mapper that synthesizes resource interfaces
public final class SynthesizedResourceInterfaceProjectMapper: ProjectMapping { // swiftlint:disable:this type_name
    private let synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating
    private let contentHasher: ContentHashing

    public convenience init(
        contentHasher: ContentHashing
    ) {
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
        guard !project.options.disableSynthesizedResourceAccessors else {
            return (project, [])
        }
        Logger.current.debug("Transforming project \(project.name): Synthesizing resource accessors")

        let targetsArray = Array(project.targets.values)
        let mappings = try targetsArray.map(context: .concurrent) { target in
            try mapTarget(target, project: project)
        }

        let targets: [Target] = mappings.map(\.0)
        let sideEffects: [SideEffectDescriptor] = mappings.map(\.1).flatMap { $0 }
        var project = project
        project.targets = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
        return (project, sideEffects)
    }

    // MARK: - Helpers

    private struct RenderedFile: Hashable {
        let path: AbsolutePath
        let contents: Data?
    }

    /// Map and generate resource interfaces for a given `Target` and `Project`
    private func mapTarget(_ target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        let resourcesForSynthesizersPaths = resourcePaths(target, project: project)
        guard !resourcesForSynthesizersPaths.isEmpty, target.supportsSources else { return (target, []) }

        let synthesizersWithTemplates = try project.resourceSynthesizers
            .map { resourceSynthesizer throws -> (ResourceSynthesizer, String) in
                switch resourceSynthesizer.template {
                case let .file(path):
                    let templateString = try FileHandler.shared.readTextFile(path)
                    return (resourceSynthesizer, templateString)
                case .defaultTemplate:
                    return (resourceSynthesizer, try templateString(for: resourceSynthesizer.parser))
                }
            }

        let results = try synthesizersWithTemplates.map(context: .concurrent) { resourceSynthesizer, templateString in
            try renderResourceInterface(
                resourceSynthesizer,
                templateString: templateString,
                target: target,
                project: project
            )
        }

        var target = target
        target.sources += results.flatMap(\.sources)
        let sideEffects = results.flatMap(\.sideEffects)

        return (target, sideEffects)
    }

    /// - Returns: Source files and side effects for a given resource synthesizer
    private func renderResourceInterface(
        _ resourceSynthesizer: ResourceSynthesizer,
        templateString: String,
        target: Target,
        project: Project
    ) throws -> (
        sources: [SourceFile],
        sideEffects: [SideEffectDescriptor]
    ) {
        let derivedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)

        let renderedInterfaces = try renderedInterfaces(
            for: resourceSynthesizer,
            templateString: templateString,
            target: target,
            project: project
        )

        let renderedResources = Set(
            renderedInterfaces.map { name, contents in
                RenderedFile(
                    path: derivedPath.appending(component: name + ".swift"),
                    contents: contents.data(using: .utf8)
                )
            }
        )

        let sources = try Array(renderedResources).map(context: .concurrent) { resource in
            let hash = try resource.contents.map(contentHasher.hash)
            return SourceFile(path: resource.path, contentHash: hash)
        }

        let sideEffects = renderedResources
            .map { FileDescriptor(path: $0.path, contents: $0.contents) }
            .map(SideEffectDescriptor.file)

        return (
            sources: sources,
            sideEffects: sideEffects
        )
    }

    private func paths(
        for resourceSynthesizer: ResourceSynthesizer,
        target: Target,
        project: Project,
        developmentRegion: String?
    ) -> [AbsolutePath] {
        let resourcesPaths = resourcePaths(target, project: project)

        var paths = resourcesPaths
            .filter { $0.extension.map(resourceSynthesizer.extensions.contains) ?? false }
            .sorted()

        switch resourceSynthesizer.parser {
        case .strings:
            // This file kind is localizable, let's order files based on it
            paths = {
                guard let developmentRegion else { return paths }
                return paths.sorted { lhs, rhs in
                    let lhsBasename = lhs.parentDirectory.basenameWithoutExt
                    let rhsBasename = rhs.parentDirectory.basenameWithoutExt

                    if lhsBasename == developmentRegion {
                        return true
                    } else if rhsBasename == developmentRegion {
                        return false
                    } else if lhsBasename.contains(developmentRegion), rhsBasename.contains(developmentRegion) {
                        return lhsBasename < rhsBasename
                    } else {
                        return lhsBasename < rhsBasename
                    }
                }
            }()
        case .plists:
            // Exclude binary plists from synthesized interface generation
            let plistChecks = paths.map(context: .concurrent) { path -> (AbsolutePath, Bool) in
                do {
                    let fileHandle = try FileHandle(forReadingFrom: path.url)
                    defer { try? fileHandle.close() }

                    let bplistSignature = "bplist00"
                    let signature = try fileHandle.read(upToCount: bplistSignature.count)
                    let isNotBinary = signature != Data(bplistSignature.utf8)
                    return (path, isNotBinary)
                } catch {
                    AlertController.current.warning(.alert("\(path.basename) is not a valid plist or unreadable."))
                    return (path, false)
                }
            }
            paths = plistChecks.filter(\.1).map(\.0)
        case .assets, .coreData, .fonts, .interfaceBuilder, .json, .yaml, .files, .stringsCatalog:
            break
        }

        var seen: Set<String> = []
        return paths.filter { seen.insert($0.basename).inserted }
    }

    private func isResourceEmpty(_ path: AbsolutePath) throws -> Bool {
        if FileHandler.shared.isFolder(path) {
            if try !FileHandler.shared.contentsOfDirectory(path).isEmpty { return true }
        } else {
            if try !FileHandler.shared.readFile(path).isEmpty { return true }
        }
        Logger.current.log(
            level: .warning,
            "Skipping synthesizing accessors for \(path.pathString) because its contents are empty."
        )
        return false
    }

    private func resourcePaths(_ target: Target, project: Project) -> [AbsolutePath] {
        let resourcePaths = target.resources.resources.map(\.path)
        let coreDataModelPaths = target.coreDataModels.map(\.path)
        let extensions = project.resourceSynthesizers.map(\.extensions).flatMap(Array.init)
        let buildableFolderResources = target.buildableFolders.flatMap { buildableFolder in
            return buildableFolder.resolvedFiles.compactMap { buildableFolderFile -> AbsolutePath? in
                guard extensions.contains(buildableFolderFile.path.extension ?? "") else { return nil }
                return buildableFolderFile.path
            }
        }
        return resourcePaths + coreDataModelPaths + buildableFolderResources
    }

    private func templateString(for parser: ResourceSynthesizer.Parser) throws -> String {
        switch parser {
        case .assets:
            return SynthesizedResourceInterfaceTemplates.assetsTemplate
        case .strings:
            return SynthesizedResourceInterfaceTemplates.stringsTemplate
        case .plists:
            return SynthesizedResourceInterfaceTemplates.plistsTemplate
        case .fonts:
            return SynthesizedResourceInterfaceTemplates.fontsTemplate
        case .coreData, .interfaceBuilder, .json, .yaml:
            throw SynthesizedResourceInterfaceProjectMapperError.defaultTemplateNotAvailable(parser)
        case .files:
            return SynthesizedResourceInterfaceTemplates.filesTemplate
        case .stringsCatalog:
            return "WIP on: https://github.com/tuist/tuist/pull/6296"
        }
    }

    private func renderedInterfaces(
        for resourceSynthesizer: ResourceSynthesizer,
        templateString: String,
        target: Target,
        project: Project
    ) throws -> [(String, String)] {
        let paths = try paths(
            for: resourceSynthesizer,
            target: target,
            project: project,
            developmentRegion: project.developmentRegion
        )
        .filter(isResourceEmpty)

        let templateName: String
        switch resourceSynthesizer.template {
        case let .defaultTemplate(name):
            templateName = name
        case let .file(path):
            templateName = path.basenameWithoutExt
        }

        let renderedInterfaces: [(String, String)]
        if paths.isEmpty {
            renderedInterfaces = []
        } else {
            let name = target.name.camelized.uppercasingFirst
            renderedInterfaces = [
                (
                    "Tuist\(templateName)+\(name)",
                    try synthesizedResourceInterfacesGenerator.render(
                        parser: resourceSynthesizer.parser,
                        parserOptions: resourceSynthesizer.parserOptions,
                        templateString: templateString,
                        name: target.productName.camelized.uppercasingFirst,
                        bundleName: project.options.disableBundleAccessors ? nil : "Bundle.module",
                        paths: paths
                    )
                ),
            ]
        }
        return renderedInterfaces
    }
}
