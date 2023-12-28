import Foundation
import TuistCore
import TuistGraph
import TuistSupport
import TSCBasic

public struct ExternalObjectiveCModulemapProjectMapper: ProjectMapping {
    private let derivedDirectoryName: String
    private let modulemapsDirectoryName: String
    
    public init(derivedDirectoryName: String = Constants.DerivedDirectory.name, 
                modulemapsDirectoryName: String = Constants.DerivedDirectory.moduleMaps) {
        self.derivedDirectoryName = derivedDirectoryName
        self.modulemapsDirectoryName = modulemapsDirectoryName
    }
    
    public func map(project: TuistGraph.Project) throws -> (TuistGraph.Project, [TuistCore.SideEffectDescriptor]) {
        guard project.isExternal else { return (project, [] )}
        
        var results = (targets: [Target](), sideEffects: [SideEffectDescriptor](), additionalProjectFiles: [AbsolutePath]())
        
        results = project.targets.reduce(into: results) { results, target in
            let (updatedTarget, sideEffects, additionalProjectFiles) = map(target: target, projectPath: project.path)
            results.targets.append(updatedTarget)
            results.sideEffects.append(contentsOf: sideEffects)
            results.additionalProjectFiles.append(contentsOf: additionalProjectFiles)
        }
        
        var project = project
        project.targets = results.targets
        project.additionalFiles.append(contentsOf: results.additionalProjectFiles.map({.file(path: $0)}))
        return (project, results.sideEffects)
    }
    
    func map(target: TuistGraph.Target, projectPath: AbsolutePath) -> (Target, [TuistCore.SideEffectDescriptor], [AbsolutePath]) {
        guard target.headers?.public.count != 0, target.settings?.base["MODULEMAP_FILE"] == nil else { return (target, [], []) }
        
        var target = target
        var publicHeaders = target.headers?.public ?? []
        let umbrellaHeaderFileName = "\(target.productName)-umbrella.h"
        
        let umbrellaHeaderContent = """
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

\(publicHeaders.map({ "#import \"\($0.basename)\""}).joined(separator: "\n"))

FOUNDATION_EXPORT double \(target.productName)VersionNumber;
FOUNDATION_EXPORT const unsigned char \(target.productName)VersionString[];
"""
        let moduleMapContent = """
framework module \(target.productName) {
  umbrella header "\(umbrellaHeaderFileName)"

  export *
  module * { export * }
}
"""

        let umbrellaHeaderPath = projectPath
            .appending(component: derivedDirectoryName)
            .appending(component: modulemapsDirectoryName)
            .appending(component: umbrellaHeaderFileName)
        let moduleMapPath = projectPath
            .appending(component: derivedDirectoryName)
            .appending(component: modulemapsDirectoryName)
            .appending(component: "\(target.productName).modulemap")
        
        let umbrellaHeaderSideEffect = SideEffectDescriptor.file(FileDescriptor(path: umbrellaHeaderPath, 
                                                                                contents: umbrellaHeaderContent.data(using: .utf8)!))
        let moduleMapSideEffect = SideEffectDescriptor.file(FileDescriptor(path: moduleMapPath, 
                                                                           contents: moduleMapContent.data(using: .utf8)!))
        
        publicHeaders.append(umbrellaHeaderPath)
        target.headers = TuistGraph.Headers(public: publicHeaders, 
                                            private: target.headers?.private ?? [],
                                            project: target.headers?.project ?? [])
        
        target.settings = target.settings?.with(base: [
            "MODULEMAP_FILE": .string("$(SRCROOT)/\(moduleMapPath.relative(to: projectPath).pathString)"),
            "PRODUCT_MODULE_NAME": .string(target.productName),
            "DEFINES_MODULE": .string("YES")
        ])

        return (target, [umbrellaHeaderSideEffect, moduleMapSideEffect], [moduleMapPath])
    }
}
