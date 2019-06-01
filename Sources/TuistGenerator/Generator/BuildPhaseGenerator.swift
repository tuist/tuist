import Basic
import Foundation
import TuistCore
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
}

final class BuildPhaseGenerator: BuildPhaseGenerating {
    // MARK: - Attributes

    func generateBuildPhases(path: AbsolutePath,
                             target: Target,
                             graph: Graphing,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             pbxproj: PBXProj,
                             sourceRootPath: AbsolutePath) throws {
        try generateActions(actions: target.actions.preActions,
                            pbxTarget: pbxTarget,
                            pbxproj: pbxproj,
                            sourceRootPath: sourceRootPath)

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

        try generateActions(actions: target.actions.postActions,
                            pbxTarget: pbxTarget,
                            pbxproj: pbxproj,
                            sourceRootPath: sourceRootPath)
    }

    func generateActions(actions: [TargetAction],
                         pbxTarget: PBXTarget,
                         pbxproj: PBXProj,
                         sourceRootPath: AbsolutePath) throws {
        try actions.forEach { action in
            let buildPhase = try PBXShellScriptBuildPhase(files: [],
                                                          name: action.name,
                                                          inputPaths: [],
                                                          outputPaths: [],
                                                          inputFileListPaths: [],
                                                          outputFileListPaths: [],
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
        try files.forEach { buildFile in
            guard let fileReference = fileElements.file(path: buildFile.path) else {
                throw BuildPhaseGenerationError.missingFileReference(buildFile.path)
            }
            var settings: [String: Any] = [:]
            if let compilerFlags = buildFile.compilerFlags {
                settings["COMPILER_FLAGS"] = compilerFlags
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

        try headers.private.forEach { try addHeader($0, "private") }
        try headers.public.forEach { try addHeader($0, "public") }
        try headers.project.forEach { try addHeader($0, "project") }
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

        try generateResourcesBuildFile(files: target.resources.map(\.path),
                                       fileElements: fileElements,
                                       pbxproj: pbxproj,
                                       resourcesBuildPhase: resourcesBuildPhase)

        generateResourceBundle(path: path,
                               target: target,
                               graph: graph,
                               fileElements: fileElements,
                               pbxproj: pbxproj,
                               resourcesBuildPhase: resourcesBuildPhase)

        target.coreDataModels.forEach {
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
        try files.forEach { buildFilePath in
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
        let refs = bundles.compactMap { fileElements.product(name: $0.target.productNameWithExtension) }
        refs.forEach {
            let pbxBuildFile = PBXBuildFile(file: $0)
            pbxproj.add(object: pbxBuildFile)
            resourcesBuildPhase.files?.append(pbxBuildFile)
        }
    }
}
