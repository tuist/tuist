import Foundation
import Path

@testable import XcodeGraph

extension XCFrameworkInfoPlist {
    public static func test(libraries: [XCFrameworkInfoPlist.Library] = [.test()]) -> XCFrameworkInfoPlist {
        XCFrameworkInfoPlist(libraries: libraries)
    }
}

extension XCFrameworkInfoPlist.Library {
    public static func test(
        identifier: String = "test",
        // swiftlint:disable:next force_try
        path: RelativePath = try! RelativePath(validating: "relative/to/library"),
        mergeable: Bool = false,
        architectures: [BinaryArchitecture] = [.i386]
    ) -> XCFrameworkInfoPlist.Library {
        XCFrameworkInfoPlist.Library(
            identifier: identifier,
            path: path,
            mergeable: mergeable,
            architectures: architectures
        )
    }
}
