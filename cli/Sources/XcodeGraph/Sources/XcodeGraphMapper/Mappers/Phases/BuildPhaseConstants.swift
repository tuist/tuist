import Foundation
import Path

/// Constants related to various build phases and their default values.
enum BuildPhaseConstants {
    /// The default name for a run script build phase if none is provided.
    static let defaultScriptName = "Run Script"
    /// The default shell path used by run script build phases.
    static let defaultShellPath = "/bin/sh"
    /// A placeholder name used when a shell script build phase has no name.
    static let unnamedScriptPhase = "Unnamed Shell Script Phase"
    /// The default name for a copy files build phase if none is provided.
    static let copyFilesDefault = "Copy Files"
}

/// Attributes indicating header visibility within a build target.
enum HeaderAttribute: String {
    /// Indicates that a header is and can be exposed outside the module.
    case `public` = "Public"
    /// Indicates that a header is private and not exposed outside the module.
    case `private` = "Private"
}

/// Attributes related to code generation behavior for source files.
enum CodeGenAttribute: String {
    /// Indicates that code generation is enabled publicly.
    case `public` = "codegen"
    /// Indicates that code generation is restricted to private scopes.
    case `private` = "private_codegen"
    /// Indicates that code generation is scoped to the project only.
    case project = "project_codegen"
    /// Indicates that code generation is disabled for the file.
    case disabled = "no_codegen"
}

/// Commonly referenced directory names within a project.
enum DirectoryName {
    /// The directory used to store headers.
    static let headers = "Headers"
}

/// Attributes that can be assigned to build files in certain build phases.
enum BuildFileAttribute: String {
    /// Indicates that the file should be code signed on copy during a copy files build phase.
    case codeSignOnCopy = "CodeSignOnCopy"
}
