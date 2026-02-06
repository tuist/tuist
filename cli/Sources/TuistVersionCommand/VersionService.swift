import Foundation
import Noora
import TuistConstants
import TuistNooraExtension

struct VersionCommandService {
    func run() throws {
        let version: String = Constants.version
        Noora.current.passthrough("\(version)\n")
    }
}
