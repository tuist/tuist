import Basic
import Foundation
import TuistCore
import xcodeproj

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
    func generateBuildPhases(target: Target,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             objects: PBXObjects) throws {
        try generateSourcesBuildPhase(files: target.sources,
                                      pbxTarget: pbxTarget,
                                      fileElements: fileElements,
                                      objects: objects)

        try generateResourcesBuildPhase(files: target.resources,
                                        coreDataModels: target.coreDataModels,
                                        pbxTarget: pbxTarget,
                                        fileElements: fileElements,
                                        objects: objects)

        if let headers = target.headers {
            try generateHeadersBuildPhase(headers: headers,
                                          pbxTarget: pbxTarget,
                                          fileElements: fileElements,
                                          objects: objects)
        }
    }

    func generateSourcesBuildPhase(files: [AbsolutePath],
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects) throws {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        objects.add(object: sourcesBuildPhase)
        pbxTarget.buildPhases.append(sourcesBuildPhase)
        try files.forEach { buildFilePath in
            guard let fileReference = fileElements.file(path: buildFilePath) else {
                throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
            }
            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: [:])
            objects.add(object: pbxBuildFile)
            sourcesBuildPhase.files.append(pbxBuildFile)
        }
    }

    func generateHeadersBuildPhase(headers: Headers,
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects) throws {
        let headersBuildPhase = PBXHeadersBuildPhase()
        objects.add(object: headersBuildPhase)
        pbxTarget.buildPhases.append(headersBuildPhase)

        let addHeader: (AbsolutePath, String) throws -> Void = { path, accessLevel in
            guard let fileReference = fileElements.file(path: path) else {
                throw BuildPhaseGenerationError.missingFileReference(path)
            }
            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: [
                "ATTRIBUTES": [accessLevel.capitalized],
            ])
            objects.add(object: pbxBuildFile)
            headersBuildPhase.files.append(pbxBuildFile)
        }

        try headers.private.forEach({ try addHeader($0, "private") })
        try headers.public.forEach({ try addHeader($0, "public") })
        try headers.project.forEach({ try addHeader($0, "project") })
    }

    func generateResourcesBuildPhase(files: [AbsolutePath] = [],
                                     coreDataModels: [CoreDataModel] = [],
                                     pbxTarget: PBXTarget,
                                     fileElements: ProjectFileElements,
                                     objects: PBXObjects) throws {
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        objects.add(object: resourcesBuildPhase)
        pbxTarget.buildPhases.append(resourcesBuildPhase)

        try generateResourcesBuildFile(files: files,
                                       fileElements: fileElements,
                                       objects: objects,
                                       resourcesBuildPhase: resourcesBuildPhase)

        coreDataModels.forEach {
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

            var element: PBXFileReference?

            if isLocalized {
                let name = buildFilePath.components.last!
                let path = buildFilePath.parentDirectory.parentDirectory.appending(component: name)
                guard let group = fileElements.group(path: path) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = group

            } else if !isLproj {
                guard let fileReference = fileElements.file(path: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                element = fileReference
            }
            if let element = element {
                let pbxBuildFile = PBXBuildFile(file: element)
                objects.add(object: pbxBuildFile)
                resourcesBuildPhase.files.append(pbxBuildFile)
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
        modelReference.currentVersion = currentVersionReference

        let pbxBuildFile = PBXBuildFile(file: modelReference)
        objects.add(object: pbxBuildFile)
        resourcesBuildPhase.files.append(pbxBuildFile)
    }
}
