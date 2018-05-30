import Basic
import Foundation
import xcodeproj

/// Errors thrown during the build phases generation.
///
/// - missingFileReference: error thrown when we try to generate a build file for a file whose reference is not in the project.
enum BuildPhaseGenerationError: FatalError, Equatable {
    case missingFileReference(AbsolutePath)

    /// Error description.
    var description: String {
        switch self {
        case let .missingFileReference(path):
            return "Trying to add a file at path \(path) to a build phase that hasn't been added to the project."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingFileReference:
            return .bugSilent
        }
    }

    /// Compares two BuildPhaseGenerationError instances.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: BuildPhaseGenerationError, rhs: BuildPhaseGenerationError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingFileReference(lhsPath), .missingFileReference(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

/// Build phase generator interface.
protocol BuildPhaseGenerating: AnyObject {
    /// Generates the build phases for a given target.
    ///
    /// - Parameters:
    ///   - targetSpec: Target specification.
    ///   - target: Xcode project target.
    ///   - fileElements: Project file elements.
    ///   - objects: Xcode project objects.
    func generateBuildPhases(targetSpec: Target,
                             target: PBXTarget,
                             fileElements: ProjectFileElements,
                             objects: PBXObjects) throws

    /// Generates the sources build phase.
    ///
    /// - Parameters:
    ///   - buildPhase: build phase specification.
    ///   - target: target whose build phase is being generated.
    ///   - fileElements: file elements instance.
    ///   - objects: project objects.
    func generateSourcesBuildPhase(_ buildPhase: SourcesBuildPhase,
                                   target: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects) throws

    /// Generates the resources build phase.
    ///
    /// - Parameters:
    ///   - buildPhase: build phase specification.
    ///   - target: target whose build phase is being generated.
    ///   - fileElements: file elements instance.
    ///   - objects: project objects.
    func generateResourcesBuildPhase(_ buildPhase: ResourcesBuildPhase,
                                     target: PBXTarget,
                                     fileElements: ProjectFileElements,
                                     objects: PBXObjects) throws
}

/// Build phase generator.
final class BuildPhaseGenerator: BuildPhaseGenerating {
    /// Generates the build phases for a given target.
    ///
    /// - Parameters:
    ///   - targetSpec: Target specification.
    ///   - target: Xcode project target.
    ///   - fileElements: Project file elements.
    ///   - objects: Xcode project objects.
    func generateBuildPhases(targetSpec: Target,
                             target: PBXTarget,
                             fileElements: ProjectFileElements,
                             objects: PBXObjects) throws {
        try targetSpec.buildPhases.forEach { buildPhase in
            if let sourcesBuildPhase = buildPhase as? SourcesBuildPhase {
                try generateSourcesBuildPhase(sourcesBuildPhase,
                                              target: target,
                                              fileElements: fileElements,
                                              objects: objects)
            } else if let resourcesBuildPhase = buildPhase as? ResourcesBuildPhase {
                try generateResourcesBuildPhase(resourcesBuildPhase,
                                                target: target,
                                                fileElements: fileElements,
                                                objects: objects)
            } else if let headersBuildPhase = buildPhase as? HeadersBuildPhase {
                try generateHeadersBuildPhase(headersBuildPhase,
                                              target: target,
                                              fileElements: fileElements,
                                              objects: objects)
            } else if let scriptBuildPhase = buildPhase as? ScriptBuildPhase {
                generateScriptBuildPhase(scriptBuildPhase,
                                         target: target,
                                         objects: objects)
            }
        }
    }

    /// Generates the sources build phase.
    ///
    /// - Parameters:
    ///   - buildPhase: build phase specification.
    ///   - target: target whose build phase is being generated.
    ///   - fileElements: file elements instance.
    ///   - objects: project objects.
    func generateSourcesBuildPhase(_ buildPhase: SourcesBuildPhase,
                                   target: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects) throws {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        let sourcesBuildPhaseReference = objects.addObject(sourcesBuildPhase)
        target.buildPhases.append(sourcesBuildPhaseReference)
        try buildPhase.buildFiles.forEach { buildFile in
            try buildFile.paths.forEach { buildFilePath in
                guard let fileReference = fileElements.file(path: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                var settings: [String: Any] = [:]
                if let compilerFlags = buildFile.compilerFlags {
                    settings["COMPILER_FLAGS"] = compilerFlags
                }
                let pbxBuildFile = PBXBuildFile(fileRef: fileReference.reference, settings: settings)
                let buildFileRerence = objects.addObject(pbxBuildFile)
                sourcesBuildPhase.files.append(buildFileRerence)
            }
        }
    }

    /// Generates a shell script build phase.
    ///
    /// - Parameters:
    ///   - buildPhase: build phase specification.
    ///   - target: Xcode project target.
    ///   - objects: Xcode project objects.
    func generateScriptBuildPhase(_ buildPhase: ScriptBuildPhase,
                                  target: PBXTarget,
                                  objects: PBXObjects) {
        let pbxBuildPhase = PBXShellScriptBuildPhase(name: buildPhase.name,
                                                     inputPaths: buildPhase.inputFiles,
                                                     outputPaths: buildPhase.outputFiles,
                                                     shellPath: buildPhase.shell,
                                                     shellScript: buildPhase.script,
                                                     showEnvVarsInLog: true)
        let pbxBuildPhaseReference = objects.addObject(pbxBuildPhase)
        target.buildPhases.append(pbxBuildPhaseReference)
    }

    /// Generates a headers build phase.
    ///
    /// - Parameters:
    ///   - buildPhase: headers build phase specification.
    ///   - target: Xcode target where the build phase will be added to.
    ///   - fileElements: project file elements.
    ///   - objects: Xcode project objects.
    func generateHeadersBuildPhase(_ buildPhase: HeadersBuildPhase,
                                   target: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects) throws {
        let headersBuildPhase = PBXHeadersBuildPhase()
        let headersBuildPhaseReference = objects.addObject(headersBuildPhase)
        target.buildPhases.append(headersBuildPhaseReference)
        try buildPhase.buildFiles.forEach { headerBuildFile in
            try headerBuildFile.paths.forEach { path in
                guard let fileReference = fileElements.file(path: path) else {
                    throw BuildPhaseGenerationError.missingFileReference(path)
                }
                let pbxBuildFile = PBXBuildFile(fileRef: fileReference.reference, settings: [
                    "ATTRIBUTES": [headerBuildFile.accessLevel.rawValue.capitalized],
                ])
                let buildFileRerence = objects.addObject(pbxBuildFile)
                headersBuildPhase.files.append(buildFileRerence)
            }
        }
    }

    /// Generates a resources build phase.
    ///
    /// - Parameters:
    ///   - buildPhase: Resources build phase specification.
    ///   - target: Xcode project target whose build phase will be generated.
    ///   - fileElements: Project file elements.
    ///   - objects: Xcode project objects.
    func generateResourcesBuildPhase(_ buildPhase: ResourcesBuildPhase,
                                     target: PBXTarget,
                                     fileElements: ProjectFileElements,
                                     objects: PBXObjects) throws {
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        let resourcesBuildPhaseReference = objects.addObject(resourcesBuildPhase)
        target.buildPhases.append(resourcesBuildPhaseReference)
        try buildPhase.buildFiles.forEach { buildFile in
            // Normal resource build file.
            if let resourcesBuildFile = buildFile as? ResourcesBuildFile {
                try generateResourcesBuildFile(resourcesBuildFile: resourcesBuildFile,
                                               fileElements: fileElements,
                                               objects: objects,
                                               resourcesBuildPhase: resourcesBuildPhase)
                // Core Data model build file.
            } else if let coreDataModelBuildFile = buildFile as? CoreDataModelBuildFile {
                generateCoreDataModel(coreDataModelBuildFile: coreDataModelBuildFile,
                                      fileElements: fileElements,
                                      objects: objects,
                                      resourcesBuildPhase: resourcesBuildPhase)
            }
        }
    }

    /// Generates a resources build file.
    ///
    /// - Parameters:
    ///   - resourcesBuildFile: Build file.
    ///   - fileElements: Project file elements.
    ///   - objects: Xcode project objects.
    ///   - resourcesBuildPhase: Resources build phase.
    private func generateResourcesBuildFile(resourcesBuildFile: ResourcesBuildFile,
                                            fileElements: ProjectFileElements,
                                            objects: PBXObjects,
                                            resourcesBuildPhase: PBXResourcesBuildPhase) throws {
        try resourcesBuildFile.paths.forEach { buildFilePath in
            let pathString = buildFilePath.asString
            let pathRange = NSRange(location: 0, length: pathString.count)
            let isLocalized = ProjectFileElements.localizedRegex.firstMatch(in: pathString, options: [], range: pathRange) != nil
            let isLproj = buildFilePath.extension == "lproj"
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
                let pbxBuildFile = PBXBuildFile(fileRef: reference)
                let buildFileRerence = objects.addObject(pbxBuildFile)
                resourcesBuildPhase.files.append(buildFileRerence)
            }
        }
    }

    /// It generates a Core Data model build file.
    ///
    /// - Parameters:
    ///   - coreDataModelBuildFile: Core Data model build file.
    ///   - fileElements: Project file elements.
    ///   - objects: Xcode Project objects.
    ///   - resourcesBuildPhase: resources build phase.
    private func generateCoreDataModel(coreDataModelBuildFile: CoreDataModelBuildFile,
                                       fileElements: ProjectFileElements,
                                       objects: PBXObjects,
                                       resourcesBuildPhase: PBXResourcesBuildPhase) {
        let currentVersion = coreDataModelBuildFile.currentVersion
        let path = coreDataModelBuildFile.path
        let currentVersionPath = path.appending(component: "\(currentVersion).xcdatamodel")
        // swiftlint:disable:next force_cast
        let modelReference = fileElements.group(path: path)! as! XCVersionGroup
        let currentVersionReference = fileElements.file(path: currentVersionPath)!
        modelReference.currentVersion = currentVersionReference.reference

        let pbxBuildFile = PBXBuildFile(fileRef: modelReference.reference)
        let buildFileRerence = objects.addObject(pbxBuildFile)
        resourcesBuildPhase.files.append(buildFileRerence)
    }
}
