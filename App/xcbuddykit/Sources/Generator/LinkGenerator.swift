import Foundation
import xcodeproj
import Basic

enum LinkGeneratorError: FatalError {
    
    var description: String {
        return ""
    }
    
    var type: ErrorType {
        return .abort
    }
}

protocol LinkGenerating: AnyObject {
    
    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       context: GeneratorContexting,
                       objects: PBXObjects,
                       pbxProject: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath) throws
    
}

final class LinkGenerator: LinkGenerating {
    
    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       context: GeneratorContexting,
                       objects: PBXObjects,
                       pbxProject: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath) throws {
        let embeddableFrameworks = try context.graph.embeddableFrameworks(path: path, name: target.name, shell: context.shell)
        let publicHeaders = context.graph.librariesPublicHeaders(path: path, name: target.name)
        let linkableModules = try context.graph.linkableDependencies(path: path, name: target.name)
        
        try generateEmbedPhase(dependencies: embeddableFrameworks,
                               pbxTarget: pbxTarget,
                               objects: objects,
                               pbxProject: pbxProject,
                               fileElements: fileElements)
        
        try setupPublicHeaders(publicHeaders,
                               pbxTarget: pbxTarget,
                               objects: objects,
                               pbxProject: pbxProject,
                               fileElements: fileElements)
        
        try generateLinkingPhase(dependencies: linkableModules,
                                 pbxTarget: pbxTarget,
                                 objects: objects,
                                 pbxProject: pbxProject,
                                 fileElements: fileElements)
    }
    
    func generateEmbedPhase(dependencies: [DependencyReference],
                            pbxTarget: PBXTarget,
                            objects: PBXObjects,
                            pbxProject: PBXProject,
                            fileElements: ProjectFileElements) throws {
        
    }
    
    func setupPublicHeaders(_ publicHeaders: [AbsolutePath],
                            pbxTarget: PBXTarget,
                            objects: PBXObjects,
                            pbxProject: PBXProject,
                            fileElements: ProjectFileElements) throws {
        
    }
    
    func generateLinkingPhase(dependencies: [DependencyReference],
                              pbxTarget: PBXTarget,
                              objects: PBXObjects,
                              pbxProject: PBXProject,
                              fileElements: ProjectFileElements) throws {
        
    }
    
}
