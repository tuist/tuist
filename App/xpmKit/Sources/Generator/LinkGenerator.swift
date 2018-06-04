import Basic
import Foundation
import xcodeproj

/// Link generator error.
///
/// - missingProduct: thrown when a product reference is missing. Product references should be generated before the linking is.
/// - missingReference: thrown when there s a file reference missing. File references should be generated before the linking is.
/// - missingConfigurationList: thrown when a target doesn't have a configuration list.
enum LinkGeneratorError: FatalError {
    case missingProduct(name: String)
    case missingReference(path: AbsolutePath)
    case missingConfigurationList(targetName: String)

    /// Error description
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

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingProduct, .missingConfigurationList, .missingReference:
            return .bugSilent
        }
    }
}

/// Generates the linking settings (build phases and build settings).
protocol LinkGenerating: AnyObject {
    /// Generates the linking for a given target.
    ///
    /// - Parameters:
    ///   - target: target specification.
    ///   - pbxTarget: Xcode project target.
    ///   - context: generation context.
    ///   - objects: Xcode project objects.
    ///   - pbxProject: Xcode PBXProject object.
    ///   - fileElements: project file elements.
    ///   - path: path to the folder where the project manifest is.
    ///   - sourceRootPath: path to the folder where the Xcode project is generated.
    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       context: GeneratorContexting,
                       objects: PBXObjects,
                       pbxProject: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath) throws
}

final class LinkGenerator: LinkGenerating {
    /// Generates the linking for a given target.
    ///
    /// - Parameters:
    ///   - target: target specification.
    ///   - pbxTarget: Xcode project target.
    ///   - context: generation context.
    ///   - objects: Xcode project objects.
    ///   - pbxProject: Xcode PBXProject object.
    ///   - fileElements: project file elements.
    ///   - path: path to the folder where the project manifest is.
    ///   - sourceRootPath: path to the folder where the Xcode project is generated.
    func generateLinks(target: Target,
                       pbxTarget: PBXTarget,
                       context: GeneratorContexting,
                       objects: PBXObjects,
                       pbxProject _: PBXProject,
                       fileElements: ProjectFileElements,
                       path: AbsolutePath,
                       sourceRootPath: AbsolutePath) throws {
        let embeddableFrameworks = try context.graph.embeddableFrameworks(path: path, name: target.name, shell: context.shell)
        let headersSearchPaths = context.graph.librariesPublicHeadersFolders(path: path, name: target.name)
        let linkableModules = try context.graph.linkableDependencies(path: path, name: target.name)

        try generateEmbedPhase(dependencies: embeddableFrameworks,
                               pbxTarget: pbxTarget,
                               objects: objects,
                               fileElements: fileElements,
                               resourceLocator: context.resourceLocator,
                               sourceRootPath: sourceRootPath)

        try setupHeadersSearchPath(headersSearchPaths,
                                   pbxTarget: pbxTarget,
                                   sourceRootPath: sourceRootPath)

        try generateLinkingPhase(dependencies: linkableModules,
                                 pbxTarget: pbxTarget,
                                 objects: objects,
                                 fileElements: fileElements)
    }

    /// Generates the frameworks embed phase.
    /// This phase copies dynamic frameworks into the products so that the dynamic linker can find them at
    /// startup time and do the linking.
    ///
    /// - Parameters:
    ///   - dependencies: list of dependencies that should be embeded.
    ///   - pbxTarget: Xcode target.
    ///   - objects: Xcode project objects.
    ///   - fileElements: project file elements.
    ///   - resourceLocator: resource locator used to get the path to the "xpm-embed" util.
    ///   - sourceRootPath: path to the folder where the Xcode project is generated.
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

        pbxTarget.buildPhases.append(precompiledEmbedPhaseReference)
        pbxTarget.buildPhases.append(embedPhaseReference)

        var script: [String] = []
        let embedPath = try resourceLocator.embedPath()

        try dependencies.forEach { dependency in
            if case let DependencyReference.absolute(path) = dependency {
                let relativePath = "$(SRCROOT)/\(path.relative(to: sourceRootPath).asString)"
                script.append("\(embedPath.asString) \(path.relative(to: sourceRootPath).asString)")
                precompiledEmbedPhase.inputPaths.append(relativePath)
                precompiledEmbedPhase.outputPaths.append("$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/\(path.components.last!)")

            } else if case let DependencyReference.product(name) = dependency {
                guard let fileRef = fileElements.product(name: name) else {
                    throw LinkGeneratorError.missingProduct(name: name)
                }
                let buildFile = PBXBuildFile(fileRef: fileRef.reference)
                let buildFileReference = objects.addObject(buildFile)
                embedPhase.files.append(buildFileReference)
            }
        }

        precompiledEmbedPhase.shellScript = script.joined(separator: "\n")
    }

    /// Setup the headers search paths.
    ///
    /// - Parameters:
    ///   - headersFolders: headers folders paths.
    ///   - pbxTarget: Xcode project target.
    ///   - objects: Xcode project objects.
    ///   - pbxProject: Xcodode PBXProject object.
    ///   - fileElements: project file elements.
    ///   - sourceRootPath: path to the folder where the project is generated.
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

    /// Generates the linking build phase.
    ///
    /// - Parameters:
    ///   - dependencies: dependencies that should be added to the linking phase.
    ///   - pbxTarget: Xcode project target.
    ///   - objects: Xcode project objects.
    ///   - pbxProject: Xcode PBXProject instance.
    ///   - fileElements: project file elements.
    func generateLinkingPhase(dependencies: [DependencyReference],
                              pbxTarget: PBXTarget,
                              objects: PBXObjects,
                              fileElements: ProjectFileElements) throws {
        let buildPhase = PBXFrameworksBuildPhase()
        let buildPhaseReference = objects.addObject(buildPhase)
        pbxTarget.buildPhases.append(buildPhaseReference)
        try dependencies.forEach { dependency in
            if case let DependencyReference.absolute(path) = dependency {
                guard let fileRef = fileElements.file(path: path) else {
                    throw LinkGeneratorError.missingReference(path: path)
                }
                let buildFile = PBXBuildFile(fileRef: fileRef.reference)
                let buildFileReference = objects.addObject(buildFile)
                buildPhase.files.append(buildFileReference)

            } else if case let DependencyReference.product(name) = dependency {
                guard let fileRef = fileElements.product(name: name) else {
                    throw LinkGeneratorError.missingProduct(name: name)
                }
                let buildFile = PBXBuildFile(fileRef: fileRef.reference)
                let buildFileReference = objects.addObject(buildFile)
                buildPhase.files.append(buildFileReference)
            }
        }
    }
}
