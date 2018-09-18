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
                             pbxproj: PBXProj) throws
}

final class BuildPhaseGenerator: BuildPhaseGenerating {
    func generateBuildPhases(target: Target,
                             pbxTarget: PBXTarget,
                             fileElements: ProjectFileElements,
                             pbxproj: PBXProj) throws {
        try generateSourcesBuildPhase(files: target.sources,
                                      pbxTarget: pbxTarget,
                                      fileElements: fileElements,
                                      pbxproj: pbxproj)

        try generateResourcesBuildPhase(files: target.resources,
                                        coreDataModels: target.coreDataModels,
                                        pbxTarget: pbxTarget,
                                        fileElements: fileElements,
                                        pbxproj: pbxproj)

        if let headers = target.headers {
            try generateHeadersBuildPhase(headers: headers,
                                          pbxTarget: pbxTarget,
                                          fileElements: fileElements,
                                          pbxproj: pbxproj)
        }
    }

    func generateSourcesBuildPhase(files: [AbsolutePath],
                                   pbxTarget: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   pbxproj: PBXProj) throws {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        pbxproj.add(object: sourcesBuildPhase)
        pbxTarget.buildPhases.append(sourcesBuildPhase)
        try files.forEach { buildFilePath in
            guard let fileReference = fileElements.file(path: buildFilePath) else {
                throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
            }
            let pbxBuildFile = PBXBuildFile(file: fileReference, settings: [:])
            pbxproj.add(object: pbxBuildFile)
            sourcesBuildPhase.files.append(pbxBuildFile)
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
                                     pbxproj: PBXProj) throws {
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        pbxproj.add(object: resourcesBuildPhase)
        pbxTarget.buildPhases.append(resourcesBuildPhase)

        try generateResourcesBuildFile(files: files,
                                       fileElements: fileElements,
                                       pbxproj: pbxproj,
                                       resourcesBuildPhase: resourcesBuildPhase)

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

            var element: PBXFileElement?

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
                pbxproj.add(object: pbxBuildFile)
                resourcesBuildPhase.files.append(pbxBuildFile)
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
        resourcesBuildPhase.files.append(pbxBuildFile)
    }
}
