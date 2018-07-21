import Basic
import Foundation
import xcodeproj
import xpmcore

enum BuildPhaseGenerationError: FatalError, Equatable {
    case missingFileReference(AbsolutePath)

    var description: String {
        switch self {
        case let .missingFileReference(path):
            return "Trying to add a file at path \(path.asString) to a build phase that hasn't been added to the project."
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
    func generateBuildPhases(target: Target,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             objects: PBXObjects) throws
}

final class BuildPhaseGenerator: BuildPhaseGenerating {
    func generateBuildPhases(target _: Target,
                             pbxTarget _: PBXTarget,
                             fileElements _: ProjectFileElements,
                             objects _: PBXObjects) throws {
        //        try target.buildPhases.forEach { buildPhase in
        //            if let sourcesBuildPhase = buildPhase as? SourcesBuildPhase {
        //                try generateSourcesBuildPhase(sourcesBuildPhase,
        //                                              pbxTarget: pbxTarget,
        //                                              fileElements: fileElements,
        //                                              objects: objects)
        //            } else if let resourcesBuildPhase = buildPhase as? ResourcesBuildPhase {
        //                try generateResourcesBuildPhase(resourcesBuildPhase,
        //                                                pbxTarget: pbxTarget,
        //                                                fileElements: fileElements,
        //                                                objects: objects)
        //            } else if let headersBuildPhase = buildPhase as? HeadersBuildPhase {
        //                try generateHeadersBuildPhase(headersBuildPhase,
        //                                              pbxTarget: pbxTarget,
        //                                              fileElements: fileElements,
        //                                              objects: objects)
        //            } else if let scriptBuildPhase = buildPhase as? ScriptBuildPhase {
        //                generateScriptBuildPhase(scriptBuildPhase,
        //                                         pbxTarget: pbxTarget,
        //                                         objects: objects)
        //            } else if let copyBuildPhase = buildPhase as? CopyBuildPhase {
        //                generateCopyBuildPhase(copyBuildPhase,
        //                                       pbxTarget: pbxTarget,
        //                                       fileElements: fileElements,
        //                                       objects: objects)
        //            }
        //        }
    }

    func generateSourcesBuildPhase(buildFiles: [AbsolutePath],
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects) throws {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        let sourcesBuildPhaseReference = objects.addObject(sourcesBuildPhase)
        pbxTarget.buildPhasesReferences.append(sourcesBuildPhaseReference)
        try buildFiles.forEach { buildFilePath in
            guard let fileReference = fileElements.file(path: buildFilePath) else {
                throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
            }
            let pbxBuildFile = PBXBuildFile(fileReference: fileReference.reference, settings: [:])
            let buildFileRerence = objects.addObject(pbxBuildFile)
            sourcesBuildPhase.fileReferences.append(buildFileRerence)
        }
    }

    func generateHeadersBuildPhase(headers: Headers,
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects) throws {
        let headersBuildPhase = PBXHeadersBuildPhase()
        let headersBuildPhaseReference = objects.addObject(headersBuildPhase)
        pbxTarget.buildPhasesReferences.append(headersBuildPhaseReference)

        let addHeader: (AbsolutePath, String) throws -> Void = { path, accessLevel in
            guard let fileReference = fileElements.file(path: path) else {
                throw BuildPhaseGenerationError.missingFileReference(path)
            }
            let pbxBuildFile = PBXBuildFile(fileReference: fileReference.reference, settings: [
                "ATTRIBUTES": [accessLevel.capitalized],
            ])
            let buildFileRerence = objects.addObject(pbxBuildFile)
            headersBuildPhase.fileReferences.append(buildFileRerence)
        }

        try headers.private.forEach({ try addHeader($0, "private") })
        try headers.public.forEach({ try addHeader($0, "public") })
        try headers.project.forEach({ try addHeader($0, "project") })
    }

    func generateResourcesBuildPhase(files: [AbsolutePath],
                                     coreDataModels: [CoreDataModel],
                                     pbxTarget: PBXTarget,
                                     fileElements: ProjectFileElements,
                                     objects: PBXObjects) throws {
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        let resourcesBuildPhaseReference = objects.addObject(resourcesBuildPhase)
        pbxTarget.buildPhasesReferences.append(resourcesBuildPhaseReference)

        try generateResourcesBuildFile(files: files,
                                       fileElements: fileElements,
                                       objects: objects,
                                       resourcesBuildPhase: resourcesBuildPhase)

        try coreDataModels.forEach {
            self.generateCoreDataModel(coreDataModel: $0,
                                       fileElements: fileElements,
                                       objects: objects,
                                       resourcesBuildPhase: resourcesBuildPhase)
        }
    }

    private func generateResourcesBuildFile(files: [AbsolutePath],
                                            fileElements: ProjectFileElements,
                                            objects: PBXObjects,
                                            resourcesBuildPhase: PBXResourcesBuildPhase) throws {
        try files.forEach { buildFilePath in
            let pathString = buildFilePath.asString
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

            var reference: PBXObjectReference?

            if isLocalized {
                let name = buildFilePath.components.last!
                let path = buildFilePath.parentDirectory.parentDirectory.appending(component: name)
                guard let group = fileElements.group(path: path) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                reference = group.reference

            } else if !isLproj {
                guard let fileReference = fileElements.file(path: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                reference = fileReference.reference
            }
            if let reference = reference {
                let pbxBuildFile = PBXBuildFile(fileReference: reference)
                let buildFileRerence = objects.addObject(pbxBuildFile)
                resourcesBuildPhase.fileReferences.append(buildFileRerence)
            }
        }
    }

    private func generateCoreDataModel(coreDataModel: CoreDataModel,
                                       fileElements: ProjectFileElements,
                                       objects: PBXObjects,
                                       resourcesBuildPhase: PBXResourcesBuildPhase) {
        let currentVersion = coreDataModel.currentVersion
        let path = coreDataModel.path
        let currentVersionPath = path.appending(component: "\(currentVersion).xcdatamodel")
        // swiftlint:disable:next force_cast
        let modelReference = fileElements.group(path: path)! as! XCVersionGroup
        let currentVersionReference = fileElements.file(path: currentVersionPath)!
        modelReference.currentVersion = currentVersionReference.reference

        let pbxBuildFile = PBXBuildFile(fileReference: modelReference.reference)
        let buildFileRerence = objects.addObject(pbxBuildFile)
        resourcesBuildPhase.fileReferences.append(buildFileRerence)
    }
}
