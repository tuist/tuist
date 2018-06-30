import Foundation

protocol GraphValidating: AnyObject {
    func validate(graph: Graph) throws
}

/// Validates the projects graph.
class GraphValidator: GraphValidating {

    // MARK: - Attributes

    /// Project validator.
    let projectValidator: ProjectValidator = ProjectValidator()

    /// Validates the given graph.
    ///
    /// - Parameter graph: graph to be validated
    /// - Throws: an error if the validation fails
    func validate(graph: Graph) throws {
        try graph.projects.forEach(projectValidator.validate)
        try ensurePlatformsAreCompatible(graph: graph)
    }

    fileprivate func ensurePlatformsAreCompatible(graph _: Graph) throws {
    }

    // TODO: Validate invalid platforms.
    // TODO: Validate invalid dependencies test -> test
}
