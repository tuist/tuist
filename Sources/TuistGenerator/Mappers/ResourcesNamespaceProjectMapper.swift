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
        
        var sideEffects: [SideEffectDescriptor] = []
        
        sideEffects += try render(
            .assets,
            target: target,
            project: project
        )
        
        // TODO: Input + output paths
        let (target, namespaceScriptSideEffects) = mapAndGenerateNamespaceScript(target, project: project)
        
        sideEffects += namespaceScriptSideEffects
        
        return (target, sideEffects)
    }
    
    // MARK: - Helpers
    
    private func render(
        _ namespaceType: NamespaceType,
        target: Target,
        project: Project
    ) throws -> [SideEffectDescriptor] {
        let derivedPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.sources)
        
        let paths = self.paths(for: namespaceType, target: target)
        
        return try namespaceGenerator.render(namespaceType, paths: paths)
            .map { name, contents in
                FileDescriptor(
                    path: derivedPath.appending(component: name + ".swift"),
                    contents: contents.data(using: .utf8)
                )
        }
        .map(SideEffectDescriptor.file)
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
        
        let sideEffects: [SideEffectDescriptor] = [
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
        #if DEBUG
        // Used only for debug purposes to find currently-built tuist
        // `bundlePath` points to .build/debug/tuist
        let tuistCommand = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .appending(components: ".build", "debug", "tuist")
            .pathString
        #else
        let tuistCommand = "tuist"
        #endif
        return """
        #!/bin/sh
        
        pushd "${SRCROOT}"
        \(tuistCommand) generate namespace
        popd
        """
    }()
}
