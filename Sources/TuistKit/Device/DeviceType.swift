import Foundation

struct DeviceType: Hashable {

    // MARK: - Attributes

    let name: String
    let identifier: String

    var hashValue: Int {
        return identifier.hashValue
    }

    // MARK: - Init

    init(name: String,
         identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}
