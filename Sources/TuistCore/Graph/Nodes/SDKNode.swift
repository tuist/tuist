import Foundation
import TSCBasic
import TuistSupport

@available(*, deprecated, message: "SDK nodes are deprecated. Dependencies should be usted instead with the ValueGraph.")
public class SDKNode: GraphNode {
    static let xctestFrameworkName = "XCTest.framework"

    public let status: SDKStatus
    public let type: SDKType
    public let source: SDKSource

    public init(name: String,
                platform: Platform,
                status: SDKStatus,
                source: SDKSource) throws {
        let sdk = AbsolutePath("/\(name)")
        // TODO: Validate using a linter
        guard let sdkExtension = sdk.extension, let type = SDKType(rawValue: sdkExtension) else {
            throw Error.unsupported(sdk: name)
        }
        self.status = status
        self.type = type
        self.source = source
        let path = try SDKNode.path(name: name, platform: platform, source: source, type: type)
        super.init(path: path, name: String(name.split(separator: ".").first!))
    }

    /// Creates an instance of SDKNode that represents the XCTest framework.
    /// - Parameters:
    ///   - platform: Platform.
    ///   - status: SDK status.
    /// - Returns: Initialized SDK node.
    public static func xctest(platform: Platform, status: SDKStatus) -> SDKNode {
        // swiftlint:disable:next force_try
        try! SDKNode(name: "XCTest.framework", platform: platform, status: status, source: .system)
    }

    /// Creates an instace of SDKNode that represents the AppClip framework.
    /// - Parameters:
    ///   - status: SDK status
    /// - Returns: Initialized SDK node.
    public static func appClip(status: SDKStatus) throws -> SDKNode {
        try SDKNode(name: "AppClip.framework", platform: .iOS, status: status, source: .system)
    }

    static func path(name: String, platform: Platform, source _: SDKSource, type: SDKType) throws -> AbsolutePath {
        let sdkRootPath: AbsolutePath
        if name == SDKNode.xctestFrameworkName {
            guard let xcodeDeveloperSdkRootPath = platform.xcodeDeveloperSdkRootPath else {
                throw Error.unsupported(sdk: name)
            }
            sdkRootPath = AbsolutePath(xcodeDeveloperSdkRootPath,
                                       relativeTo: AbsolutePath("/"))
            return sdkRootPath
                .appending(RelativePath("Frameworks"))
                .appending(component: name)
        } else {
            sdkRootPath = AbsolutePath(platform.xcodeSdkRootPath,
                                       relativeTo: AbsolutePath("/"))
            switch type {
            case .framework:
                return sdkRootPath
                    .appending(RelativePath("System/Library/Frameworks"))
                    .appending(component: name)
            case .library:
                return sdkRootPath
                    .appending(RelativePath("usr/lib"))
                    .appending(component: name)
            }
        }
    }

    enum Error: FatalError, Equatable {
        case unsupported(sdk: String)
        var description: String {
            switch self {
            case let .unsupported(sdk):
                let supportedTypes = SDKType.supportedTypesDescription
                return "The SDK type of \(sdk) is not currently supported - only \(supportedTypes) are supported."
            }
        }

        var type: ErrorType {
            switch self {
            case .unsupported:
                return .abort
            }
        }
    }
}
