import Foundation

/// Enum whose cases represent different destinations where projects can be generated.
///
/// - manifest: Generates the workspace and the project in the same folder where the project manifest is.
/// - derivedProjects: Generates the workspace and the project in the ~/.tuist/DerivedProjects directory.
enum GenerationDirectory {
    case manifest
    case derivedProjects
}
