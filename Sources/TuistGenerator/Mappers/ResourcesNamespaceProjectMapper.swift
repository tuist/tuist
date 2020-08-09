import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// A project mapper that generates namespace for resources
public final class ResourcesNamespaceProjectMapper: ProjectMapping {
    private let namespaceGenerator: NamespaceGenerating
    
    public convenience init() {
        self.init(namespaceGenerator: NamespaceGenerator())
    }
    
    init(
        namespaceGenerator: NamespaceGenerating
    ) {
        self.namespaceGenerator = namespaceGenerator
    }
    
    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        let mappings = try project.targets
            .map { try mapTarget($0, project: project) }
        
        let targets: [Target] = mappings.map(\.0)
        let sideEffects: [SideEffectDescriptor] = mappings.map(\.1).flatMap { $0 }
        
        return (project.with(targets: targets), sideEffects)
    }
    
    // MARK: - Helpers
    
    /// Map and generate namespace for a given `Target` and `Project`
    private func mapTarget(_ target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        guard !target.resources.isEmpty else { return (target, []) }
        
        var target = target
        
        var sideEffects: [SideEffectDescriptor] = []
        var inputPaths: [AbsolutePath] = []
        var outputPaths: [AbsolutePath] = []
        
        let assetsSideEffects: [SideEffectDescriptor]
        let assetsInputPaths: [AbsolutePath]
        let assetsOutputPaths: [AbsolutePath]
        (target, assetsSideEffects, assetsInputPaths, assetsOutputPaths) = try renderAndMapTarget(
            .assets,
            target: target,
            project: project
        )
        sideEffects += assetsSideEffects
        inputPaths += assetsInputPaths
        outputPaths += assetsOutputPaths
        
        let stringsSideEffects: [SideEffectDescriptor]
        let stringsInputPaths: [AbsolutePath]
        let stringsOutputPaths: [AbsolutePath]
        (target, stringsSideEffects, stringsInputPaths, stringsOutputPaths) = try renderAndMapTarget(
            .strings,
            target: target,
            project: project
        )
        sideEffects += stringsSideEffects
        inputPaths += stringsInputPaths
        outputPaths += stringsOutputPaths
        
        let namespaceScriptSideEffects: [SideEffectDescriptor]
        (target, namespaceScriptSideEffects) = mapAndGenerateNamespaceScript(
            target,
            project: project,
            inputPaths: inputPaths,
            outputPaths: outputPaths
        )
        
        sideEffects += namespaceScriptSideEffects
        
        return (target, sideEffects)
    }

    /// - Returns: Modified `Target`, side effects, input paths and output paths which can then be later used in generate script
    private func renderAndMapTarget(
        _ namespaceType: NamespaceType,
        target: Target,
        project: Project
    ) throws -> (
        target: Target,
        sideEffects: [SideEffectDescriptor],
        inputPaths: [AbsolutePath],
        outputPaths: [AbsolutePath]
    ) {
        let derivedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
        
        let paths = self.paths(for: namespaceType, target: target)
        
        let renderedResources = try namespaceGenerator.render(namespaceType, paths: paths)
            .map { name, contents in
                (path: derivedPath.appending(component: name + ".swift"),
                 contents: contents.data(using: .utf8))
        }
        
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
            outputPaths: renderedResources.map(\.path)
        )
    }
    
    private func paths(for namespaceType: NamespaceType, target: Target) -> [AbsolutePath] {
        let resourcesPaths = target.resources
            .map(\.path)
        switch namespaceType {
        case .assets:
            return resourcesPaths
                .filter(\.isFolder)
                .filter { $0.extension == "xcassets" }
        case .strings:
            return resourcesPaths
                .filter { $0.extension == "strings" }
        }
    }
    
    private func mapAndGenerateNamespaceScript(
        _ target: Target,
        project: Project,
        inputPaths: [AbsolutePath],
        outputPaths: [AbsolutePath]
    ) -> (Target, [SideEffectDescriptor]) {
        let generateNamespaceScriptPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: "generate_namespace.sh")
        
        var target = target
        target.actions.append(
            TargetAction(
                name: "Generate namespace",
                order: .pre,
                path: generateNamespaceScriptPath,
                skipLint: true,
                inputPaths: inputPaths,
                outputPaths: outputPaths
            )
        )
        
        let sideEffects: [SideEffectDescriptor] = [
            .file(
                FileDescriptor(
                    path: generateNamespaceScriptPath,
                    contents: namespaceGenerator.generateNamespaceScript().data(using: .utf8)
                )
            ),
            .command(
                CommandDescriptor(
                    command: "chmod", "+x", generateNamespaceScriptPath.pathString
                )
            ),
        ]
        
        return (target, sideEffects)
    }
}
