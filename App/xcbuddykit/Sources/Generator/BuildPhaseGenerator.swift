import Basic
import Foundation
import xcodeproj

/// Errors thrown during the build phases generation.
///
/// - missingFileReference: error thrown when we try to generate a build file for a file whose reference is not in the project.
enum BuildPhaseGenerationError: FatalError, Equatable {
    case missingFileReference(AbsolutePath)
    case duplicatedFile(AbsolutePath, targetName: String)

    /// Error description.
    var description: String {
        switch self {
        case let .missingFileReference(path):
            return "Trying to add a file at path \(path) to a build phase that hasn't been added to the project."
        case let .duplicatedFile(path, targetName):
            return "The build file at path \(path) is duplicated in the target '\(targetName)'"
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingFileReference:
            return .bugSilent
        case .duplicatedFile:
            return .abort
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
        default:
            return false
        }
    }
}

/// Build phase generator interface.
protocol BuildPhaseGenerating: AnyObject {
    func generateBuildPhases(targetSpec: Target,
                             target: PBXTarget,
                             fileElements: ProjectFileElements,
                             objects: PBXObjects,
                             context: GeneratorContexting) throws

    /// Generates the sources build phase.
    ///
    /// - Parameters:
    ///   - buildPhase: build phase specification.
    ///   - target: target whose build phase is being generated.
    ///   - fileElements: file elements instance.
    ///   - objects: project objects.
    ///   - context: generation context.
    func generateSourcesBuildPhase(_ buildPhase: SourcesBuildPhase,
                                   target: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects,
                                   context: GeneratorContexting) throws
}

/// Build phase generator.
final class BuildPhaseGenerator: BuildPhaseGenerating {
    func generateBuildPhases(targetSpec: Target,
                             target: PBXTarget,
                             fileElements: ProjectFileElements,
                             objects: PBXObjects,
                             context: GeneratorContexting) throws {
        try targetSpec.buildPhases.forEach { buildPhase in
            if let sourcesBuildPhase = buildPhase as? SourcesBuildPhase {
                try generateSourcesBuildPhase(sourcesBuildPhase,
                                              target: target,
                                              fileElements: fileElements,
                                              objects: objects,
                                              context: context)
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
    ///   - context: generation context.
    func generateSourcesBuildPhase(_ buildPhase: SourcesBuildPhase,
                                   target: PBXTarget,
                                   fileElements: ProjectFileElements,
                                   objects: PBXObjects,
                                   context _: GeneratorContexting) throws {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        let sourcesBuildPhaseReference = objects.addObject(sourcesBuildPhase)
        target.buildPhases.append(sourcesBuildPhaseReference)
        var buildFiles: [AbsolutePath: PBXBuildFile] = [:]
        try buildPhase.buildFiles.forEach { buildFile in
            try buildFile.paths.forEach { buildFilePath in
                if buildFiles[buildFilePath] != nil {
                    throw BuildPhaseGenerationError.duplicatedFile(buildFilePath, targetName: target.name)
                }
                guard let fileReference = fileElements.file(path: buildFilePath) else {
                    throw BuildPhaseGenerationError.missingFileReference(buildFilePath)
                }
                var settings: [String: Any] = [:]
                if let compilerFlags = buildFile.compilerFlags {
                    settings["COMPILER_FLAGS"] = compilerFlags
                }
                let pbxBuildFile = PBXBuildFile(fileRef: fileReference.reference, settings: settings)
                buildFiles[buildFilePath] = pbxBuildFile
                let buildFileRerence = objects.addObject(pbxBuildFile)
                sourcesBuildPhase.files.append(buildFileRerence)
            }
        }
    }
}
