import Foundation
import Path
import XcodeGraph

// MARK: - Provider Errors

public enum SystemFrameworkMetadataProviderError: LocalizedError, Equatable {
    case unsupportedSDK(name: String)
    case unsupportedSDKPlatform(sdk: String, platform: Platform, supported: [Platform])

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSDK(sdk):
            let supportedTypes = SDKType.supportedTypesDescription
            return "The SDK type of \(sdk) is not currently supported - only \(supportedTypes) are supported."
        case let .unsupportedSDKPlatform(sdk, platform, supported):
            let platforms = supported.map(\.caseValue).joined(separator: ", ")
            return "The Platform type of \(platform.caseValue) is not currently supported for \(sdk) - only \(platforms) are supported."
        }
    }
}

// MARK: - Provider

public protocol SystemFrameworkMetadataProviding {
    func loadMetadata(sdkName: String, status: LinkingStatus, platform: Platform, source: SDKSource) throws
        -> SystemFrameworkMetadata
}

extension SystemFrameworkMetadataProviding {
    public func loadXCTestMetadata(platform: Platform) throws -> SystemFrameworkMetadata {
        try loadMetadata(sdkName: "XCTest.framework", status: .required, platform: platform, source: .developer)
    }
}

// MARK: - Default Implementation

public final class SystemFrameworkMetadataProvider: SystemFrameworkMetadataProviding {
    public init() {}

    public func loadMetadata(
        sdkName: String,
        status: LinkingStatus,
        platform: Platform,
        source sdkSource: SDKSource
    ) throws -> SystemFrameworkMetadata {
        let sdkNamePath = try AbsolutePath(validating: "/\(sdkName)")
        guard let sdkExtension = sdkNamePath.extension
        else { throw SystemFrameworkMetadataProviderError.unsupportedSDK(name: sdkName) }

        let sdkType: SDKType
        switch sdkExtension {
        case "framework":
            sdkType = .framework
        case "tbd":
            if sdkName.starts(with: "libswift") {
                sdkType = .swiftLibrary
            } else {
                sdkType = .library
            }
        default:
            throw SystemFrameworkMetadataProviderError.unsupportedSDK(name: sdkName)
        }

        var source = sdkSource
        if sdkName == "XcodeKit.framework" {
            source = .developer
            if platform != .macOS {
                throw SystemFrameworkMetadataProviderError
                    .unsupportedSDKPlatform(sdk: sdkName, platform: platform, supported: [.macOS])
            }
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
            let xcodeDeveloperSdkRootPath = name == "XcodeKit.framework" ? "Library" : platform.xcodeDeveloperSdkRootPath
            let sdkRootPath = try AbsolutePath(validating: "/\(xcodeDeveloperSdkRootPath)")
            return sdkRootPath
                .appending(try RelativePath(validating: "Frameworks"))
                .appending(component: name)

        case .system:
            let sdkRootPath = try AbsolutePath(validating: "/\(platform.xcodeSdkRootPath)")
            switch type {
            case .framework:
                return sdkRootPath
                    .appending(try RelativePath(validating: "System/Library/Frameworks"))
                    .appending(component: name)
            case .library:
                return sdkRootPath
                    .appending(try RelativePath(validating: "usr/lib"))
                    .appending(component: name)
            case .swiftLibrary:
                return sdkRootPath
                    .appending(components: "usr", "lib", "swift", name)
            }
        }
    }
}
