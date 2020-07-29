import Foundation

/// Up that configures a Homebrew tap in the system.
class UpHomebrewCask: Up {
    /// Project to be installed with Homebrew Cask.
    let projects: [String]

    /// Initializes the up Homebrew Cask with its attributes.
    ///
    /// - Parameter projects: Project to be installed with Homebrew Cask.
    init(projects: [String]) {
        self.projects = projects
        super.init()
    }

    public enum CodingKeys: String, CodingKey {
        case projects
        case type
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decode([String].self, forKey: .projects)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projects, forKey: .projects)
        try container.encode("homebrew-cask", forKey: .type)
    }

    override func equals(_ other: Up) -> Bool {
        guard let otherUpHomebrewTap = other as? UpHomebrewCask else { return false }
        return projects == otherUpHomebrewTap.projects
    }
}
