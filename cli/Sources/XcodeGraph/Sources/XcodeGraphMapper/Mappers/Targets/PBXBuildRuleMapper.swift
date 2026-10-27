import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol defining how to map a single `PBXBuildRule` instance into a `BuildRule` domain model.
///
/// Conforming types transform an individual build rule defined in an Xcode project into a
/// structured `BuildRule` model, enabling further analysis or code generation steps to operate on
/// well-defined representations of build rules.
protocol BuildRuleMapping {
    /// Maps a single `PBXBuildRule` into a `BuildRule` model.
    ///
    /// - Parameter buildRule: The `PBXBuildRule` to map.
    /// - Returns: A `BuildRule` model if the compiler spec and file type are recognized; otherwise, `nil`.
    /// - Throws: If resolving or mapping the build rule fails.
    func map(_ buildRule: PBXBuildRule) throws -> BuildRule?
}

/// A mapper that converts a `PBXBuildRule` object into a `BuildRule` domain model.
///
/// `BuildRuleMapper` extracts known compiler specs and file types from the provided build rule.
/// If the compiler spec or file type is unknown, the build rule is ignored (returning `nil`).
struct PBXBuildRuleMapper: BuildRuleMapping {
    func map(_ buildRule: PBXBuildRule) throws -> BuildRule? {
        let compilerSpec = try mapCompilerSpec(buildRule.compilerSpec)
        let fileType = try mapFileType(buildRule.fileType)

        return BuildRule(
            compilerSpec: compilerSpec,
            fileType: fileType,
            filePatterns: buildRule.filePatterns,
            name: buildRule.name,
            outputFiles: buildRule.outputFiles,
            inputFiles: buildRule.inputFiles,
            outputFilesCompilerFlags: buildRule.outputFilesCompilerFlags,
            script: buildRule.script,
            runOncePerArchitecture: buildRule.runOncePerArchitecture
        )
    }

    // MARK: - Private Helpers

    private func mapCompilerSpec(_ compilerSpec: String) throws -> BuildRule.CompilerSpec {
        try BuildRule.CompilerSpec(rawValue: compilerSpec)
            .throwing(PBXBuildRuleMappingError.unknownCompilerSpec(compilerSpec))
    }

    private func mapFileType(_ fileType: String) throws -> BuildRule.FileType {
        try BuildRule.FileType(rawValue: fileType)
            .throwing(PBXBuildRuleMappingError.unknownFileType(fileType))
    }
}

enum PBXBuildRuleMappingError: Error, LocalizedError, Equatable {
    case unknownFileType(String)
    case unknownCompilerSpec(String)

    var errorDescription: String? {
        switch self {
        case let .unknownFileType(fileType):
            return "Unknown file type: \(fileType)"
        case let .unknownCompilerSpec(compilerSpec):
            return "Unknown compiler spec: \(compilerSpec)"
        }
    }
}
