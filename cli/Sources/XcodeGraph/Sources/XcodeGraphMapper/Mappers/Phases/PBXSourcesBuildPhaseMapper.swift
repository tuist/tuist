import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol for mapping a PBXSourcesBuildPhase into an array of SourceFile models.
protocol PBXSourcesBuildPhaseMapping {
    /// Converts the given sources build phase into a list of `SourceFile`s.
    /// - Parameters:
    ///   - sourcesBuildPhase: The build phase that may contain source files.
    ///   - xcodeProj: The `XcodeProj` used for path resolution.
    /// - Returns: A sorted list of `SourceFile`s by their path.
    /// - Throws: If file paths are invalid or unavailable.
    func map(_ sourcesBuildPhase: PBXSourcesBuildPhase, xcodeProj: XcodeProj) throws -> [SourceFile]
}

/// The default mapper that converts a `PBXSourcesBuildPhase` to an array of `SourceFile`s.
struct PBXSourcesBuildPhaseMapper: PBXSourcesBuildPhaseMapping {
    func map(
        _ sourcesBuildPhase: PBXSourcesBuildPhase,
        xcodeProj: XcodeProj
    ) throws -> [SourceFile] {
        let files = sourcesBuildPhase.files ?? []
        return try files
            .compactMap { try mapSourceFile($0, xcodeProj: xcodeProj) }
            .sorted { $0.path < $1.path }
    }

    // MARK: - Private Helpers

    /// Maps a single `PBXBuildFile` into a `SourceFile` if valid.
    private func mapSourceFile(
        _ buildFile: PBXBuildFile,
        xcodeProj: XcodeProj
    ) throws -> SourceFile? {
        guard let fileRef = buildFile.file,
              let pathString = try fileRef.fullPath(sourceRoot: xcodeProj.srcPathString)
        else {
            return nil
        }

        let path = try AbsolutePath(validating: pathString)
        let compilerFlags: String? = buildFile.compilerFlags
        let attributes: [String]? = buildFile.attributes

        return SourceFile(
            path: path,
            compilerFlags: compilerFlags,
            codeGen: mapCodeGenAttribute(attributes)
        )
    }

    /// Translates file attributes into a `FileCodeGen`, if specified.
    private func mapCodeGenAttribute(_ attributes: [String]?) -> FileCodeGen? {
        guard let attributes else { return nil }

        switch true {
        case attributes.contains(FileCodeGen.public.rawValue):
            return .public
        case attributes.contains(FileCodeGen.private.rawValue):
            return .private
        case attributes.contains(FileCodeGen.project.rawValue):
            return .project
        case attributes.contains(FileCodeGen.disabled.rawValue):
            return .disabled
        default:
            return nil
        }
    }
}
