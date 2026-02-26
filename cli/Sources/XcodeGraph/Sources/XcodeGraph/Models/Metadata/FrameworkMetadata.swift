import Foundation
import Path

/// The metadata associated with a precompiled framework (.framework)
public struct FrameworkMetadata: Equatable {
    public var path: AbsolutePath
    public var binaryPath: AbsolutePath
    public var dsymPath: AbsolutePath?
    public var bcsymbolmapPaths: [AbsolutePath]
    public var linking: BinaryLinking
    public var architectures: [BinaryArchitecture]
    public var status: LinkingStatus

    public init(
        path: AbsolutePath,
        binaryPath: AbsolutePath,
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        status: LinkingStatus
    ) {
        self.path = path
        self.binaryPath = binaryPath
        self.dsymPath = dsymPath
        self.bcsymbolmapPaths = bcsymbolmapPaths
        self.linking = linking
        self.architectures = architectures
        self.status = status
    }
}

#if DEBUG
    extension FrameworkMetadata {
        public static func test(
            // swiftlint:disable:next force_try
            path: AbsolutePath = try! AbsolutePath(validating: "/Frameworks/TestFramework.xframework"),
            // swiftlint:disable:next force_try
            binaryPath: AbsolutePath = try! AbsolutePath(validating: "/Frameworks/TestFramework.xframework/TestFramework"),
            dsymPath: AbsolutePath? = nil,
            bcsymbolmapPaths: [AbsolutePath] = [],
            linking: BinaryLinking = .dynamic,
            architectures: [BinaryArchitecture] = [.arm64],
            status: LinkingStatus = .required
        ) -> FrameworkMetadata {
            FrameworkMetadata(
                path: path,
                binaryPath: binaryPath,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                status: status
            )
        }
    }
#endif
