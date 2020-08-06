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
    
    public func mapTarget(_ target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        guard !target.resources.isEmpty else { return (target, []) }
        
        let imageFolders: [AbsolutePath] = target.resources
            .map(\.path)
            .filter(\.isFolder)
            .filter { $0.extension == "xcassets" }
        
        let derivedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
        
        var sideEffects: [SideEffectDescriptor] = []
        
        sideEffects += try namespaceGenerator.renderAssets(imageFolders)
            .map { name, contents in
                FileDescriptor(
                    path: derivedPath.appending(component: name + ".swift"),
                    contents: contents.data(using: .utf8)
                )
        }
        .map(SideEffectDescriptor.file)
        
        let generateNamespaceScriptPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: "generate_namespace.sh")
        
        // TODO: Input + output paths
        let target = target.with(
            actions: target.actions + [
                TargetAction(
                    name: "Generate namespace",
                    order: .pre,
                    path: generateNamespaceScriptPath,
                    skipLint: true
                )
            ]
        )
        
        sideEffects += [
            .file(
                FileDescriptor(
                    path: generateNamespaceScriptPath,
                    contents: ResourcesNamespaceProjectMapper.generateNamespaceScript.data(using: .utf8)
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
    
    private static let generateNamespaceScript: String = {
        """
        #!/bin/sh
        
        pushd "${SRCROOT}"
        tuist generate namespace
        popd
        """
    }()
}
