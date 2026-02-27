import Foundation
import Path

/// The metadata associated with a precompiled library (.a / .dylib)
public struct LibraryMetadata: Equatable {
    public var path: AbsolutePath
    public var publicHeaders: AbsolutePath
    public var swiftModuleMap: AbsolutePath?
    public var architectures: [BinaryArchitecture]
    public var linking: BinaryLinking

    public init(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?,
        architectures: [BinaryArchitecture],
        linking: BinaryLinking
    ) {
        self.path = path
        self.publicHeaders = publicHeaders
        self.swiftModuleMap = swiftModuleMap
        self.architectures = architectures
        self.linking = linking
    }
}

#if DEBUG
    extension LibraryMetadata {
        public static func test(
            // swiftlint:disable:next force_try
            path: AbsolutePath = try! AbsolutePath(validating: "/Libraries/libTest/libTest.a"),
            // swiftlint:disable:next force_try
            publicHeaders: AbsolutePath = try! AbsolutePath(validating: "/Libraries/libTest/include"),
            // swiftlint:disable:next force_try
            swiftModuleMap: AbsolutePath? = try! AbsolutePath(validating: "/Libraries/libTest/libTest.swiftmodule"),
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
#endif
