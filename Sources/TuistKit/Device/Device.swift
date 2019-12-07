import Foundation

struct Device: Hashable, Equatable {
    // MARK: - Attributes

    let state: String
    let availability: String
    let name: String
    let udid: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(udid)
    }

    var available: Bool {
        !availability.contains("unavailable")
    }

    // MARK: - Init

    init(state: String,
         availability: String,
         name: String,
         udid: String) {
        self.state = state
        self.availability = availability
        self.name = name
        self.udid = udid
    }
}
