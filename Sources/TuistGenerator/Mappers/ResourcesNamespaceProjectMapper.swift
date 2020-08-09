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
    
    private func mapTarget(_ target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        guard !target.resources.isEmpty else { return (target, []) }
        
        var target = target
        
        var sideEffects: [SideEffectDescriptor] = []
        
        let assetsSideEffects: [SideEffectDescriptor]
        (target, assetsSideEffects) = try renderAndMapTarget(
            .assets,
            target: target,
            project: project
        )
        sideEffects += assetsSideEffects
        
        // TODO: Input + output paths
        let namespaceScriptSideEffects: [SideEffectDescriptor]
        (target, namespaceScriptSideEffects) = mapAndGenerateNamespaceScript(target, project: project)
        
        sideEffects += namespaceScriptSideEffects
        
        return (target, sideEffects)
    }
    
    private func renderAndMapTarget(
        _ namespaceType: NamespaceType,
        target: Target,
        project: Project
    ) throws -> (Target, [SideEffectDescriptor]) {
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
        
        target.sources += target.sources + renderedResources
            .map(\.path)
            .map { (path: $0, compilerFlags: nil) }
        
        let sideEffects = renderedResources
        .map { FileDescriptor(path: $0.path, contents: $0.contents) }
        .map(SideEffectDescriptor.file)
        
        return (target, sideEffects)
    }
    
    private func paths(for namespaceType: NamespaceType, target: Target) -> [AbsolutePath] {
        let resourcesPaths = target.resources
            .map(\.path)
        switch namespaceType {
        case .assets:
            return resourcesPaths
                .filter(\.isFolder)
                .filter { $0.extension == "xcassets" }
        }
    }
    
    private func mapAndGenerateNamespaceScript(_ target: Target, project: Project) -> (Target, [SideEffectDescriptor]) {
        let generateNamespaceScriptPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: "generate_namespace.sh")
        
        var target = target
        target.actions.append(
            TargetAction(
                name: "Generate namespace",
                order: .pre,
                path: generateNamespaceScriptPath,
                skipLint: true
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
