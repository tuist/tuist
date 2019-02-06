import Foundation

struct Runtime: Equatable, Hashable {
    // MARK: - Attributes

    let buildVersion: String
    let availability: String
    let name: String
    let version: String
    let identifier: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    // MARK: - Init

    init(buildVersion: String,
         availability: String,
         name: String,
         identifier: String,
         version: String) {
        self.buildVersion = buildVersion
        self.availability = availability
        self.name = name
        self.identifier = identifier
        self.version = version
    }
}
