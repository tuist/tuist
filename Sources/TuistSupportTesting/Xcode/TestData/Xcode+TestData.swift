import Foundation
import TSCBasic

import TuistSupport

extension Xcode {
    static func test(
        path: AbsolutePath = try! AbsolutePath(validating: "/Applications/Xcode.app"), // swiftlint:disable:this force_try
        infoPlist: Xcode.InfoPlist = .test()
    ) -> Xcode {
        Xcode(path: path, infoPlist: infoPlist)
    }
}

extension Xcode.InfoPlist {
    static func test(version: String = "3.2.1") -> Xcode.InfoPlist {
        Xcode.InfoPlist(version: version)
    }
}
