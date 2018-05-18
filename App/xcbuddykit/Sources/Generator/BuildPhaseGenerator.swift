import Basic
import Foundation
import xcodeproj

/// Errors thrown during the build phases generation.
///
/// - missingFileReference: error thrown when we try to generate a build file for a file whose reference is not in the project.
enum BuildPhaseGenerationError: Error, Equatable, ErrorStringConvertible {
    case missingFileReference(AbsolutePath)

    var errorDescription: String {
        switch self {
        case let .missingFileReference(path):
            return "Trying to add a file at path \(path) to a build phase that hasn't been added to the project."
        }
    }

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
                             context: GeneratorContexting)

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
                                   context: GeneratorContexting)
}

/// Build phase generator.
final class BuildPhaseGenerator: BuildPhaseGenerating {
    func generateBuildPhases(targetSpec: Target,
                             target: PBXTarget,
                             fileElements: ProjectFileElements,
                             objects: PBXObjects,
                             context: GeneratorContexting) {
        targetSpec.buildPhases.forEach { buildPhase in
            if let sourcesBuildPhase = buildPhase as? SourcesBuildPhase {
                generateSourcesBuildPhase(sourcesBuildPhase,
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
                                   context: GeneratorContexting) {
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        let sourcesBuildPhaseReference = objects.addObject(sourcesBuildPhase)
        target.buildPhases.append(sourcesBuildPhaseReference)
        buildPhase.buildFiles.files.forEach { path in
            guard let fileReference = fileElements.file(path: path) else {
                context.errorHandler.fatal(error: FatalError.bugSilent(BuildPhaseGenerationError.missingFileReference(path)))
                return
            }
            let buildFile = PBXBuildFile(fileRef: fileReference.reference)
            let buildFileReference = objects.addObject(buildFile)
            sourcesBuildPhase.files.append(buildFileReference)
        }
    }
}
