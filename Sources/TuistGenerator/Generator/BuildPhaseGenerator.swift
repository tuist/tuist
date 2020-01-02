import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

enum BuildPhaseGenerationError: FatalError, Equatable {
    case missingFileReference(AbsolutePath)

    var description: String {
        switch self {
        case let .missingFileReference(path):
            return "Trying to add a file at path \(path.pathString) to a build phase that hasn't been added to the project."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingFileReference:
            return .bug
        }
    }

    static func == (lhs: BuildPhaseGenerationError, rhs: BuildPhaseGenerationError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingFileReference(lhsPath), .missingFileReference(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

protocol BuildPhaseGenerating: AnyObject {
    func generateBuildPhases(path: AbsolutePath,
                             target: Target,
                             graph: Graphing,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             pbxproj: PBXProj,
                             sourceRootPath: AbsolutePath) throws

    /// Generates target actions
    ///
    /// - Parameters:
    ///   - actions: Actions to be generated as script build phases.
    ///   - pbxTarget: PBXTarget from the Xcode project.
    ///   - pbxproj: PBXProj instance.
    ///   - sourceRootPath: Path to the directory that will contain the generated project.
    /// - Throws: An error if the script phase can't be generated.
    func generateActions(actions: [TargetAction],
                         pbxTarget: PBXTarget,
                         pbxproj: PBXProj,
                         sourceRootPath: AbsolutePath) throws
}

// swiftlint:disable:next type_body_length
final class BuildPhaseGenerator: BuildPhaseGenerating {
    // MARK: - Attributes

    func generateBuildPhases(path: AbsolutePath,
                             target: Target,
                             graph: Graphing,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             pbxproj: PBXProj,
                             sourceRootPath _: AbsolutePath) throws {
        if let headers = target.headers {
            try generateHeadersBuildPhase(headers: headers,
                                          pbxTarget: pbxTarget,
                                          fileElements: fileElements,
                                          pbxproj: pbxproj)
        }

        try generateSourcesBuildPhase(files: target.sources,
                                      pbxTarget: pbxTarget,
                                      fileElements: fileElements,
                                      pbxproj: pbxproj)

        try generateResourcesBuildPhase(path: path,
                                        target: target,
                                        graph: graph,
                                        pbxTarget: pbxTarget,
                                        fileElements: fileElements,
                                        pbxproj: pbxproj)

        try generateAppExtensionsBuildPhase(path: path,
                                            target: target,
                                            graph: graph,
                                            pbxTarget: pbxTarget,
                                            fileElements: fileElements,
                                            pbxproj: pbxproj)

        try generateEmbedWatchBuildPhase(path: path,
                                         target: target,
                                         graph: graph,
                                         pbxTarget: pbxTarget,
                                         fileElements: fileElements,
                                         pbxproj: pbxproj)
    }

    func generateActions(actions: [TargetAction],
                         pbxTarget: PBXTarget,
                         pbxproj: PBXProj,
                         sourceRootPath: AbsolutePath) throws {
        try actions.forEach { action in
            let buildPhase = try PBXShellScriptBuildPhase(files: [],
                                                          name: action.name,
                                                          inputPaths: action.inputPaths.map { $0.relative(to: sourceRootPath).pathString },
                                                          outputPaths: action.outputPaths.map { $0.relative(to: sourceRootPath).pathString },
                                                          inputFileListPaths: action.inputFileListPaths.map { $0.relative(to: sourceRootPath).pathString }, // swiftlint:disable:this line_length
                                                          
                                                          outputFileListPaths: action.outputFileListPaths.map { $0.relative(to: sourceRootPath).pathString }, // swiftlint:disable:this line_length
                                                          
                                                          shellPath: "/bin/sh",
                                                          shellScript: action.shellScript(sourceRootPath: sourceRootPath))
            pbxproj.add(object: buildPhase)
            pbxTarget.buildPhases.append(buildPhase)
        }
    }

    func generateSourcesBuildPhase(files: [Target.SourceFile],
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   pbxproj: PBXProj) throws {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        pbxproj.add(object: sourcesBuildPhase)
        pbxTarget.buildPhases.append(sourcesBuildPhase)

        let sortedFiles = files.sorted(by: { $0.path < $1.path })
        try sortedFiles.forEach { buildFile in
            guard let fileReference = fileElements.file(path: buildFile.path) else {
                throw BuildPhaseGenerationError.missingFileReference(buildFile.path)
            }
            var settings: [String: Any]?
            if let compilerFlags = buildFile.compilerFlags {
                settings = [
                    "COMPILER_FLAGS": compilerFlags,
                ]
            }

            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: settings)
            pbxproj.add(object: pbxBuildFile)
            sourcesBuildPhase.files?.append(pbxBuildFile)
        }
    }

    func generateHeadersBuildPhase(headers: Headers,
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   pbxproj: PBXProj) throws {
        let headersBuildPhase = PBXHeadersBuildPhase()
        pbxproj.add(object: headersBuildPhase)
        pbxTarget.buildPhases.append(headersBuildPhase)

        let addHeader: (AbsolutePath, String) throws -> Void = { path, accessLevel in
            guard let fileReference = fileElements.file(path: path) else {
                throw BuildPhaseGenerationError.missingFileReference(path)
            }
            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: [
                "ATTRIBUTES": [accessLevel.capitalized],
            ])
            pbxproj.add(object: pbxBuildFile)
            headersBuildPhase.files?.append(pbxBuildFile)
        }

        try headers.private.sorted().forEach { try addHeader($0, "private") }
        try headers.public.sorted().forEach { try addHeader($0, "public") }
        try headers.project.sorted().forEach { try addHeader($0, "project") }
    }

    func generateResourcesBuildPhase(path: AbsolutePath,
                                     target: Target,
                                     graph: Graphing,
                                     pbxTarget: PBXTarget,
                                     fileElements: ProjectFileElements,
                                     pbxproj: PBXProj) throws {
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        pbxproj.add(object: resourcesBuildPhase)
        pbxTarget.buildPhases.append(resourcesBuildPhase)

        try generateResourcesBuildFile(files: target.resources.flatMap({ $0.paths }),
                                       fileElements: fileElements,
                                       pbxproj: pbxproj,
                                       resourcesBuildPhase: resourcesBuildPhase)

        generateResourceBundle(path: path,
                               target: target,
                               graph: graph,
                               fileElements: fileElements,
                               pbxproj: pbxproj,
                               resourcesBuildPhase: resourcesBuildPhase)

        let coreDataModels = target.coreDataModels.sorted { $0.path < $1.path }
        coreDataModels.forEach {
            self.generateCoreDataModel(coreDataModel: $0,
                                       fileElements: fileElements,
                                       pbxproj: pbxproj,
                                       resourcesBuildPhase: resourcesBuildPhase)
        }
    }

    private func generateResourcesBuildFile(files: [AbsolutePath],
                                            fileElements: ProjectFileElements,
                                            pbxproj: PBXProj,
                                            resourcesBuildPhase: PBXResourcesBuildPhase) throws {
        var buildFilesCache = Set<AbsolutePath>()
        try files.sorted().forEach { buildFilePath in
            let pathString = buildFilePath.pathString
            let pathRange = NSRange(location: 0, length: pathString.count)
            let isLocalized = ProjectFileElements.localizedRegex.firstMatch(in: pathString, options: [], range: pathRange) != nil
            let isLproj = buildFilePath.extension == "lproj"
            let isAsset = ProjectFileElements.assetRegex.firstMatch(in: pathString, options: [], range: pathRange) != nil

            /// Assets that are part of a .xcassets folder
            /// are not added individually. The whole folder is added
            /// instead as a group.
            if isAsset {
                return
            }

            var element: (element: PBXFileElement, path: AbsolutePath)?

            if isLocalized {
                let name = buildFilePath.components.last!
                let path = buildFilePath.parentDirectory.parentDirectory.appending(component: name)
                guard let group = fileElements.group(path: path) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = (group, path)
            } else if !isLproj {
                guard let fileReference = fileElements.file(path: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = (fileReference, buildFilePath)
            }
            if let element = element, buildFilesCache.contains(element.path) == false {
                let pbxBuildFile = PBXBuildFile(file: element.element)
                pbxproj.add(object: pbxBuildFile)
                resourcesBuildPhase.files?.append(pbxBuildFile)
                buildFilesCache.insert(element.path)
            }
        }
    }

    private func generateCoreDataModel(coreDataModel: CoreDataModel,
                                       fileElements: ProjectFileElements,
                                       pbxproj: PBXProj,
                                       resourcesBuildPhase: PBXResourcesBuildPhase) {
        let currentVersion = coreDataModel.currentVersion
        let path = coreDataModel.path
        let currentVersionPath = path.appending(component: "\(currentVersion).xcdatamodel")
        // swiftlint:disable:next force_cast
        let modelReference = fileElements.group(path: path)! as! XCVersionGroup
        let currentVersionReference = fileElements.file(path: currentVersionPath)!
        modelReference.currentVersion = currentVersionReference

        let pbxBuildFile = PBXBuildFile(file: modelReference)
        pbxproj.add(object: pbxBuildFile)
        resourcesBuildPhase.files?.append(pbxBuildFile)
    }

    private func generateResourceBundle(path: AbsolutePath,
                                        target: Target,
                                        graph: Graphing,
                                        fileElements: ProjectFileElements,
                                        pbxproj: PBXProj,
                                        resourcesBuildPhase: PBXResourcesBuildPhase) {
        let bundles = graph.resourceBundleDependencies(path: path, name: target.name)
        let sortedBundles = bundles.sorted { $0.target.name < $1.target.name }
        let refs = sortedBundles.compactMap { fileElements.product(target: $0.target.name) }

        refs.forEach {
            let pbxBuildFile = PBXBuildFile(file: $0)
            pbxproj.add(object: pbxBuildFile)
            resourcesBuildPhase.files?.append(pbxBuildFile)
        }
    }

    func generateAppExtensionsBuildPhase(path: AbsolutePath,
                                         target: Target,
                                         graph: Graphing,
                                         pbxTarget: PBXTarget,
                                         fileElements: ProjectFileElements,
                                         pbxproj: PBXProj) throws {
        let appExtensions = graph.appExtensionDependencies(path: path, name: target.name)
        guard !appExtensions.isEmpty else { return }

        let appExtensionsBuildPhase = PBXCopyFilesBuildPhase(dstSubfolderSpec: .plugins, name: "Embed App Extensions")
        pbxproj.add(object: appExtensionsBuildPhase)
        pbxTarget.buildPhases.append(appExtensionsBuildPhase)

        let sortedAppExtensions = appExtensions.sorted { $0.target.name < $1.target.name }
        let refs = sortedAppExtensions.compactMap { fileElements.product(target: $0.target.name) }

        refs.forEach {
            let pbxBuildFile = PBXBuildFile(file: $0)
            pbxproj.add(object: pbxBuildFile)
            appExtensionsBuildPhase.files?.append(pbxBuildFile)
        }
    }

    func generateEmbedWatchBuildPhase(path: AbsolutePath,
                                      target: Target,
                                      graph: Graphing,
                                      pbxTarget: PBXTarget,
                                      fileElements: ProjectFileElements,
                                      pbxproj: PBXProj) throws {
        let targetDependencies = graph.targetDependencies(path: path, name: target.name)
        let watchApps = targetDependencies.filter { $0.target.product == .watch2App }
        guard !watchApps.isEmpty else { return }

        let embedWatchAppBuildPhase = PBXCopyFilesBuildPhase(dstPath: "$(CONTENTS_FOLDER_PATH)/Watch",
                                                             dstSubfolderSpec: .productsDirectory,
                                                             name: "Embed Watch Content")
        pbxproj.add(object: embedWatchAppBuildPhase)
        pbxTarget.buildPhases.append(embedWatchAppBuildPhase)

        let sortedWatchApps = watchApps.sorted { $0.target.name < $1.target.name }
        let refs = sortedWatchApps.compactMap { fileElements.product(target: $0.target.name) }

        refs.forEach {
            let pbxBuildFile = PBXBuildFile(file: $0)
            pbxproj.add(object: pbxBuildFile)
            embedWatchAppBuildPhase.files?.append(pbxBuildFile)
        }
    }
}
