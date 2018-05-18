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
        try buildPhase.buildFiles.files.forEach { path in
            guard let fileReference = fileElements.file(path: path) else {
                throw BuildPhaseGenerationError.missingFileReference(path)
            }
            let buildFile = PBXBuildFile(fileRef: fileReference.reference)
            let buildFileReference = objects.addObject(buildFile)
            sourcesBuildPhase.files.append(buildFileReference)
        }
    }
}
