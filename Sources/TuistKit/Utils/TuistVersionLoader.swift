import Foundation
import TuistSupport

protocol TuistVersionLoading {
    func getVersion() throws -> String
}

final class TuistVersionLoader: TuistVersionLoading {
    private let system: Systeming

    init(system: Systeming = System.shared) {
        self.system = system
    }

    func getVersion() throws -> String {
        try system.capture(["tuist", "version"])
    }
}
