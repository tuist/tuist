import Foundation
import TSCBasic
import TuistSupport

public class SDKNode: GraphNode {
    public let status: SDKStatus
    public let type: Type

    public init(name: String,
                platform: Platform,
                status: SDKStatus) throws {
        let sdk = AbsolutePath("/\(name)")
        // TODO: Validate using a linter
        guard let sdkExtension = sdk.extension,
            let type = Type(rawValue: sdkExtension) else {
            throw Error.unsupported(sdk: name)
        }

        self.status = status
        self.type = type

        let path: AbsolutePath
        let sdkRootPath: AbsolutePath
        if name == "XCTest.framework" {
            guard let xcodeDeveloperSdkRootPath = platform.xcodeDeveloperSdkRootPath else {
                throw Error.unsupported(sdk: name)
            }
            sdkRootPath = AbsolutePath(xcodeDeveloperSdkRootPath,
                                       relativeTo: AbsolutePath("/"))
            path = sdkRootPath
                    .appending(RelativePath("Frameworks"))
                    .appending(component: name)
        } else {
            sdkRootPath = AbsolutePath(platform.xcodeSdkRootPath,
                                       relativeTo: AbsolutePath("/"))
            switch type {
            case .framework:
                path = sdkRootPath
                    .appending(RelativePath("System/Library/Frameworks"))
                    .appending(component: name)
            case .library:
                path = sdkRootPath
                    .appending(RelativePath("usr/lib"))
                    .appending(component: name)
            }
        }

        super.init(path: path, name: String(name.split(separator: ".").first!))
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
