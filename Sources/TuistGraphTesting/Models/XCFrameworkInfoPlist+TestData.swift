import Foundation
import TSCBasic

@testable import TuistGraph

extension XCFrameworkInfoPlist {
    public static func test(libraries: [XCFrameworkInfoPlist.Library] = [.test()]) -> XCFrameworkInfoPlist {
        XCFrameworkInfoPlist(libraries: libraries)
    }
}

extension XCFrameworkInfoPlist.Library {
    public static func test(
        identifier: String = "test",
        path: RelativePath = RelativePath("relative/to/library"),
        architectures: [BinaryArchitecture] = [.i386]
    ) -> XCFrameworkInfoPlist.Library {
        XCFrameworkInfoPlist.Library(
            identifier: identifier,
            path: path,
            architectures: architectures
        )
    }
}
