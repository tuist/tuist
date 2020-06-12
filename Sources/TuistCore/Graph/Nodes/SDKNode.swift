import Foundation
import TSCBasic
import TuistSupport

public enum SDKSource {
    case developer // Platforms/iPhoneOS.platform/Developer/Library
    case system // Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library

    /// Returns the framewok search path that should be used in Xcode to locate the SDK.
    public var frameworkSearchPath: String {
        switch self {
        case .developer:
            return "$(DEVELOPER_FRAMEWORKS_DIR)"
        case .system:
            return "$(PLATFORM_DIR)/Developer/Library/Frameworks"
        }
    }
}

public class SDKNode: GraphNode {
    static let xctestFrameworkName = "XCTest.framework"

    public let status: SDKStatus
    public let type: Type
    public let source: SDKSource

    public init(name: String,
                platform: Platform,
                status: SDKStatus,
                source: SDKSource) throws {
        let sdk = AbsolutePath("/\(name)")
        // TODO: Validate using a linter
        guard let sdkExtension = sdk.extension, let type = Type(rawValue: sdkExtension) else {
            throw Error.unsupported(sdk: name)
        }
        self.status = status
        self.type = type
        self.source = source
        let path = try SDKNode.path(name: name, platform: platform, source: source, type: type)
        super.init(path: path, name: String(name.split(separator: ".").first!))
    }

    static func path(name: String, platform: Platform, source _: SDKSource, type: Type) throws -> AbsolutePath {
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

    public enum `Type`: String, CaseIterable {
        case framework
        case library = "tbd"

        static var supportedTypesDescription: String {
            let supportedTypes = allCases
                .map { ".\($0.rawValue)" }
                .joined(separator: ", ")
            return "[\(supportedTypes)]"
        }
    }

    enum Error: FatalError, Equatable {
        case unsupported(sdk: String)
        var description: String {
            switch self {
            case let .unsupported(sdk):
                let supportedTypes = Type.supportedTypesDescription
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
