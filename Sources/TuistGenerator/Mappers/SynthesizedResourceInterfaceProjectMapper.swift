import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// A project mapper that synthezies resource interfaces
public final class SynthesizedResourceInterfaceProjectMapper: ProjectMapping {
    private let synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating

    public convenience init() {
        self.init(synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerator())
    }

    init(
        synthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating
    ) {
        self.synthesizedResourceInterfacesGenerator = synthesizedResourceInterfacesGenerator
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
        var inputPaths: [AbsolutePath] = []
        var outputPaths: Set<AbsolutePath> = []

        let assetsSideEffects: [SideEffectDescriptor]
        let assetsInputPaths: [AbsolutePath]
        let assetsOutputPaths: Set<AbsolutePath>
        (target, assetsSideEffects, assetsInputPaths, assetsOutputPaths) = try renderAndMapTarget(
            .assets,
            target: target,
            project: project
        )
        sideEffects += assetsSideEffects
        inputPaths += assetsInputPaths
        outputPaths.formUnion(assetsOutputPaths)

        let stringsSideEffects: [SideEffectDescriptor]
        let stringsInputPaths: [AbsolutePath]
        let stringsOutputPaths: Set<AbsolutePath>
        (target, stringsSideEffects, stringsInputPaths, stringsOutputPaths) = try renderAndMapTarget(
            .strings,
            target: target,
            project: project
        )
        sideEffects += stringsSideEffects
        inputPaths += stringsInputPaths
        outputPaths.formUnion(stringsOutputPaths)

        let plistsSideEffects: [SideEffectDescriptor]
        let plistsInputPaths: [AbsolutePath]
        let plistsOutputPaths: Set<AbsolutePath>
        (target, plistsSideEffects, plistsInputPaths, plistsOutputPaths) = try renderAndMapTarget(
            .plists,
            target: target,
            project: project
        )
        sideEffects += plistsSideEffects
        inputPaths += plistsInputPaths
        outputPaths.formUnion(plistsOutputPaths)

        let fontsSideEffects: [SideEffectDescriptor]
        let fontsInputPaths: [AbsolutePath]
        let fontsOutputPaths: Set<AbsolutePath>
        (target, fontsSideEffects, fontsInputPaths, fontsOutputPaths) = try renderAndMapTarget(
            .fonts,
            target: target,
            project: project
        )
        sideEffects += fontsSideEffects
        inputPaths += fontsInputPaths
        outputPaths.formUnion(fontsOutputPaths)

        return (target, sideEffects)
    }

    /// - Returns: Modified `Target`, side effects, input paths and output paths which can then be later used in generate script
    private func renderAndMapTarget(
        _ synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        target: Target,
        project: Project
        // swiftlint:disable:next large_tuple
    ) throws -> (
        target: Target,
        sideEffects: [SideEffectDescriptor],
        inputPaths: [AbsolutePath],
        outputPaths: Set<AbsolutePath>
    ) {
        let derivedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)

        let paths = self.paths(for: synthesizedResourceInterfaceType, target: target)

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

        target.sources += renderedResources
            .map(\.path)
            .map { (path: $0, compilerFlags: nil) }

        let sideEffects = renderedResources
            .map { FileDescriptor(path: $0.path, contents: $0.contents) }
            .map(SideEffectDescriptor.file)

        return (
            target: target,
            sideEffects: sideEffects,
            inputPaths: paths,
            outputPaths: Set(renderedResources.map(\.path))
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
                .filter(\.isFolder)
                .filter { $0.extension == "xcassets" }
        case .strings:
            var seen: Set<String> = []
            return resourcesPaths
                .filter { $0.extension == "strings" }
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
}
