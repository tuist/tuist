import Foundation

/// CarthageDependency contains the description of a dependency to be fetched with Carthage.
struct CarthageDependency {
    /// Name of the dependency
    let name: String

    /// Type of requirement for the given dependency
    let requirement: Requirement
}
