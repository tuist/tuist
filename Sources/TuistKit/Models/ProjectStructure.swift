import Foundation

struct ProjectStructure {
    /// The group within the project/target files will be placed
    /// If `nil` the main group will be used.
    var filesGroup: String?

    static var `default`: ProjectStructure {
        return ProjectStructure(filesGroup: "Project")
    }
}
