import Foundation
import TSCBasic

@testable import TuistCore

public extension XCFrameworkInfoPlist {
    static func test(libraries: [XCFrameworkInfoPlist.Library] = [.test()]) -> XCFrameworkInfoPlist {
        XCFrameworkInfoPlist(libraries: libraries)
    }
}

public extension XCFrameworkInfoPlist.Library {
    static func test(identifier: String = "test",
                     path: RelativePath = RelativePath("relative/to/library"),
                     architectures: [BinaryArchitecture] = [.i386]) -> XCFrameworkInfoPlist.Library
    {
        XCFrameworkInfoPlist.Library(identifier: identifier,
                                     path: path,
                                     architectures: architectures)
    }
}
