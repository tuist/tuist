import Foundation
import TSCBasic
@testable import TuistGraph

extension LibraryMetadata {
    public static func test(
        path: AbsolutePath = "/Libraries/libTest/libTest.a",
        publicHeaders: AbsolutePath = "/Libraries/libTest/include",
        swiftModuleMap: AbsolutePath? = "/Libraries/libTest/libTest.swiftmodule",
        architectures: [BinaryArchitecture] = [.arm64],
        linking: BinaryLinking = .static
    ) -> LibraryMetadata {
        LibraryMetadata(
            path: path,
            publicHeaders: publicHeaders,
            swiftModuleMap: swiftModuleMap,
            architectures: architectures,
            linking: linking
        )
    }
}
