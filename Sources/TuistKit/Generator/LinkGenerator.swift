import Basic
import Foundation
import TuistCore
import xcodeproj

enum LinkGeneratorError: FatalError, Equatable {
    case missingProduct(name: String)
    case missingReference(path: AbsolutePath)
    case missingConfigurationList(targetName: String)

    var description: String {
        switch self {
        case let .missingProduct(name):
            return "Couldn't find a reference for the product \(name)."
        case let .missingReference(path):
            return "Couldn't find a reference for the file at path \(path.asString)."
        case let .missingConfigurationList(targetName):
            return "The target \(targetName) doesn't have a configuration list."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingProduct, .missingConfigurationList, .missingReference:
            return .bug
        }
    }

    static func == (lhs: LinkGeneratorError, rhs: LinkGeneratorError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingProduct(lhsName), .missingProduct(rhsName)):
            return lhsName == rhsName
        case let (.missingReference(lhsPath), .missingReference(rhsPath)):
            return lhsPath == rhsPath
        case let (.missingConfigurationList(lhsName), .missingConfigurationList(rhsName)):
            return lhsName == rhsName
        default:
            return false
        }
    }
}

protocol LinkGenerating: AnyObject {
    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       objects: PBXObjects,
                       pbxProject: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath,
                       graph: Graphing,
                       resourceLocator: ResourceLocating,
                       system: Systeming) throws
}

final class LinkGenerator: LinkGenerating {
    // MARK: - LinkGenerating

    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       objects: PBXObjects,
                       pbxProject _: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath,
                       graph: Graphing,
                       resourceLocator: ResourceLocating = ResourceLocator(),
                       system: Systeming = System()) throws {
        let embeddableFrameworks = try graph.embeddableFrameworks(path: path, name: target.name, system: system)
        let headersSearchPaths = graph.librariesPublicHeadersFolders(path: path, name: target.name)
        let linkableModules = try graph.linkableDependencies(path: path, name: target.name)

        try generateEmbedPhase(dependencies: embeddableFrameworks,
                               pbxTarget: pbxTarget,
                               objects: objects,
                               fileElements: fileElements,
                               resourceLocator: resourceLocator,
                               sourceRootPath: sourceRootPath)

        try setupFrameworkSearchPath(dependencies: linkableModules,
                                     pbxTarget: pbxTarget,
                                     sourceRootPath: sourceRootPath)

        try setupHeadersSearchPath(headersSearchPaths,
                                   pbxTarget: pbxTarget,
                                   sourceRootPath: sourceRootPath)

        try generateLinkingPhase(dependencies: linkableModules,
                                 pbxTarget: pbxTarget,
                                 objects: objects,
                                 fileElements: fileElements)
    }

    func generateEmbedPhase(dependencies: [DependencyReference],
                            pbxTarget: PBXTarget,
                            objects: PBXObjects,
                            fileElements: ProjectFileElements,
                            resourceLocator: ResourceLocating,
                            sourceRootPath: AbsolutePath) throws {
        let precompiledEmbedPhase = PBXShellScriptBuildPhase(name: "Embed Precompiled Frameworks")
        let embedPhase = PBXCopyFilesBuildPhase(dstSubfolderSpec: .frameworks,
                                                name: "Embed Frameworks")
        let precompiledEmbedPhaseReference = objects.addObject(precompiledEmbedPhase)
        let embedPhaseReference = objects.addObject(embedPhase)

        pbxTarget.buildPhasesReferences.append(precompiledEmbedPhaseReference)
        pbxTarget.buildPhasesReferences.append(embedPhaseReference)

        var script: [String] = []
        let cliPath = try resourceLocator.cliPath()

        try dependencies.forEach { dependency in
            if case let DependencyReference.absolute(path) = dependency {
                let relativePath = "$(SRCROOT)/\(path.relative(to: sourceRootPath).asString)"
                script.append("\(cliPath.asString) embed \(path.relative(to: sourceRootPath).asString)")
                precompiledEmbedPhase.inputPaths.append(relativePath)
                precompiledEmbedPhase.outputPaths.append("$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/\(path.components.last!)")

            } else if case let DependencyReference.product(name) = dependency {
                guard let fileRef = fileElements.product(name: name) else {
                    throw LinkGeneratorError.missingProduct(name: name)
                }
                let buildFile = PBXBuildFile(fileReference: fileRef.reference)
                let buildFileReference = objects.addObject(buildFile)
                embedPhase.fileReferences.append(buildFileReference)
            }
        }
        if script.count == 0 {
            precompiledEmbedPhase.shellScript = "echo \"Skipping, nothing to be embedded.\""
        } else {
            precompiledEmbedPhase.shellScript = script.joined(separator: "\n")
        }
    }

    func setupFrameworkSearchPath(dependencies: [DependencyReference],
                                  pbxTarget: PBXTarget,
                                  sourceRootPath: AbsolutePath) throws {
        let paths = dependencies.compactMap { (dependency: DependencyReference) -> AbsolutePath? in
            if case let .absolute(path) = dependency { return path }
            return nil
        }
        .map({ $0.removingLastComponent() })
        .map({ $0.relative(to: sourceRootPath).asString })
        .map({ "$(SRCROOT)/\($0)" })
        if paths.isEmpty { return }

        let configurationList = try pbxTarget.buildConfigurationList()
        let buildConfigurations = try configurationList?.buildConfigurations()

        let pathsValue = Set(paths).joined(separator: " ")
        buildConfigurations?.forEach { buildConfiguration in
            var frameworkSearchPaths = (buildConfiguration.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? String) ?? ""
            if frameworkSearchPaths.isEmpty {
                frameworkSearchPaths = pathsValue
            } else {
                frameworkSearchPaths.append(" \(pathsValue)")
            }
            buildConfiguration.buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkSearchPaths
        }
    }

    func setupHeadersSearchPath(_ headersFolders: [AbsolutePath],
                                pbxTarget: PBXTarget,
                                sourceRootPath: AbsolutePath) throws {
        let relativePaths = headersFolders
            .map({ $0.relative(to: sourceRootPath).asString })
            .map({ "$(SRCROOT)/\($0)" })
        guard let configurationList = try pbxTarget.buildConfigurationList() else {
            throw LinkGeneratorError.missingConfigurationList(targetName: pbxTarget.name)
        }
        try configurationList.buildConfigurations().forEach {
            var headers = ($0.buildSettings["HEADER_SEARCH_PATHS"] as? String) ?? ""
            headers.append(" \(relativePaths.joined(separator: " "))")
            $0.buildSettings["HEADER_SEARCH_PATHS"] = headers
        }
    }

    func generateLinkingPhase(dependencies: [DependencyReference],
                              pbxTarget: PBXTarget,
                              objects: PBXObjects,
                              fileElements: ProjectFileElements) throws {
        let buildPhase = PBXFrameworksBuildPhase()
        let buildPhaseReference = objects.addObject(buildPhase)
        pbxTarget.buildPhasesReferences.append(buildPhaseReference)
        try dependencies.forEach { dependency in
            if case let DependencyReference.absolute(path) = dependency {
                guard let fileRef = fileElements.file(path: path) else {
                    throw LinkGeneratorError.missingReference(path: path)
                }
                let buildFile = PBXBuildFile(fileReference: fileRef.reference)
                let buildFileReference = objects.addObject(buildFile)
                buildPhase.fileReferences.append(buildFileReference)

            } else if case let DependencyReference.product(name) = dependency {
                guard let fileRef = fileElements.product(name: name) else {
                    throw LinkGeneratorError.missingProduct(name: name)
                }
                let buildFile = PBXBuildFile(fileReference: fileRef.reference)
                let buildFileReference = objects.addObject(buildFile)
                buildPhase.fileReferences.append(buildFileReference)
            }
        }
    }
}
