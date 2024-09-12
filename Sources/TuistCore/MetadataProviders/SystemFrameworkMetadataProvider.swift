import Foundation
import Path
import TuistSupport
import XcodeGraph

// MARK: - Provider Errors

public enum SystemFrameworkMetadataProviderError: FatalError, Equatable {
    case unsupportedSDK(name: String)

    public var description: String {
        switch self {
        case let .unsupportedSDK(sdk):
            let supportedTypes = SDKType.supportedTypesDescription
            return "The SDK type of \(sdk) is not currently supported - only \(supportedTypes) are supported."
        }
    }

    public var type: ErrorType {
        switch self {
        case .unsupportedSDK:
            return .abort
        }
    }
}

// MARK: - Provider

public protocol SystemFrameworkMetadataProviding {
    func loadMetadata(sdkName: String, status: LinkingStatus, platform: Platform, source: SDKSource) throws
        -> SystemFrameworkMetadata
}

extension SystemFrameworkMetadataProviding {
    func loadXCTestMetadata(platform: Platform) throws -> SystemFrameworkMetadata {
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
        source: SDKSource
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
            let xcodeDeveloperSdkRootPath = platform.xcodeDeveloperSdkRootPath
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
