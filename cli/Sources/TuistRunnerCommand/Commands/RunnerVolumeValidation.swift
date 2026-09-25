import ArgumentParser
import Foundation

enum RunnerVolumeValidation {
    static func validateID(_ value: String) throws {
        guard UUID(uuidString: value) != nil else { throw ValidationError("Volume ID must be a UUID.") }
    }
}
