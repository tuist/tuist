import Foundation
import PathKit
import Unbox

class Settings: Unboxable {
    class Configuration: Unboxable {
        let settings: [String: String]
        let xcconfig: Path?

        init(settings: [String: String] = [:], xcconfig: Path? = nil) {
            self.settings = settings
            self.xcconfig = xcconfig
        }

        required init(unboxer: Unboxer) throws {
            settings = try unboxer.unbox(key: "settings")
            xcconfig = unboxer.unbox(key: "xcconfig")
            try xcconfig?.assertRelative()
        }
    }

    let base: [String: String]
    let debug: Configuration?
    let release: Configuration?

    init(base: [String: String] = [:],
         debug: Configuration?,
         release: Configuration?) {
        self.base = base
        self.debug = debug
        self.release = release
    }

    required init(unboxer: Unboxer) throws {
        base = try unboxer.unbox(key: "base")
        debug = unboxer.unbox(key: "debug")
        release = unboxer.unbox(key: "release")
    }
}
