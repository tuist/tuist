import Foundation

struct DeviceType: Hashable {
    // MARK: - Attributes

    let name: String
    let identifier: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    // MARK: - Init

    init(name: String,
         identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}
