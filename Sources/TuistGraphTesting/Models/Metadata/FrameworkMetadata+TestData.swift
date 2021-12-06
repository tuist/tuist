import Foundation
import TSCBasic
@testable import TuistGraph

extension FrameworkMetadata {
    public static func test(
        path: AbsolutePath = "/Frameworks/TestFramework.xframework",
        binaryPath: AbsolutePath = "/Frameworks/TestFramework.xframework/TestFramework",
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.arm64],
        isCarthage: Bool = false
    ) -> FrameworkMetadata {
        FrameworkMetadata(
            path: path,
            binaryPath: binaryPath,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures,
            isCarthage: isCarthage
        )
    }
}
