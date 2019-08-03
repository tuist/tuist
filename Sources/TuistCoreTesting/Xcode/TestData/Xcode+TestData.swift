import Basic
import Foundation

@testable import TuistCore

extension Xcode {
    static func test(path: AbsolutePath = AbsolutePath("/Applications/Xcode.app"),
                     infoPlist: Xcode.InfoPlist = .test()) -> Xcode {
        return Xcode(path: path, infoPlist: infoPlist)
    }
}

extension Xcode.InfoPlist {
    static func test(version: String = "3.2.1") -> Xcode.InfoPlist {
        return Xcode.InfoPlist(version: version)
    }
}
