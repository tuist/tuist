import Foundation
import TSCBasic
import TuistSupport

// MARK: - Provider Errors

public enum SystemFrameworkMetadataProviderError: FatalError, Equatable {
    case unsupportedSDK(name: String)
    case unsupportedSDKForPlatform(name: String, platform: Platform)

    public var description: String {
        switch self {
        case let .unsupportedSDK(sdk):
            let supportedTypes = SDKType.supportedTypesDescription
            return "The SDK type of \(sdk) is not currently supported - only \(supportedTypes) are supported."
        case let .unsupportedSDKForPlatform(name: sdk, platform: platform):
            return "The SDK \(sdk) is not currently supported on \(platform)."
        }
    }

    public var type: ErrorType {
        switch self {
        case .unsupportedSDK, .unsupportedSDKForPlatform:
            return .abort
        }
    }
}

// MARK: - Provider

public protocol SystemFrameworkMetadataProviding {
    func loadMetadata(sdkName: String, status: SDKStatus, platform: Platform, source: SDKSource) throws -> SystemFrameworkMetadata
}

extension SystemFrameworkMetadataProviding {
    func loadXCTestMetadata(platform: Platform) throws -> SystemFrameworkMetadata {
        try loadMetadata(sdkName: "XCTest.framework", status: .required, platform: platform, source: .developer)
    }
}

// MARK: - Default Implementation

public final class SystemFrameworkMetadataProvider: SystemFrameworkMetadataProviding {
    public init() {}

    public func loadMetadata(sdkName: String, status: SDKStatus, platform: Platform, source: SDKSource) throws -> SystemFrameworkMetadata {
        let sdkNamePath = AbsolutePath("/\(sdkName)")
        guard let sdkExtension = sdkNamePath.extension,
            let sdkType = SDKType(rawValue: sdkExtension)
        else {
            throw SystemFrameworkMetadataProviderError.unsupportedSDK(name: sdkName)
        }
        let path = try sdkPath(name: sdkName, platform: platform, type: sdkType, source: source)
        return SystemFrameworkMetadata(
            name: sdkName,
            path: path,
            status: status,
            source: source
        )
    }

    private func sdkPath(name: String, platform: Platform, type: SDKType, source: SDKSource) throws -> AbsolutePath {
        switch source {
        case .developer:
            guard let xcodeDeveloperSdkRootPath = platform.xcodeDeveloperSdkRootPath else {
                throw SystemFrameworkMetadataProviderError.unsupportedSDKForPlatform(name: name, platform: platform)
            }
            let sdkRootPath = AbsolutePath("/\(xcodeDeveloperSdkRootPath)")
            return sdkRootPath
                .appending(RelativePath("Frameworks"))
                .appending(component: name)

        case .system:
            let sdkRootPath = AbsolutePath("/\(platform.xcodeSdkRootPath)")
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
}
