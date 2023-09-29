import Foundation
@testable import TuistEnvKit

final class MockSettingsController: SettingsControlling {
    var settingsCount: UInt = 0
    var settingsStub: Settings?
    var setSettingsStub: ((Settings) throws -> Void)?
    var setSettingsCount: UInt = 0

    func settings() throws -> Settings {
        settingsCount += 1
        if let settingsStub { return settingsStub }
        return Settings()
    }

    func set(settings: Settings) throws {
        setSettingsCount += 1
        try setSettingsStub?(settings)
    }
}
