import Foundation
import TSCBasic

public enum SDKStatus: String, Codable {
    case required
    case optional
}

public enum TargetDependency: Equatable, Hashable, Codable {
    case target(name: String)
    case project(target: String, path: AbsolutePath)
    case framework(path: AbsolutePath)
    case xcFramework(path: AbsolutePath)
    case library(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?)
    case package(product: String)
    case sdk(name: String, status: SDKStatus)
    case cocoapods(path: AbsolutePath)
    case xctest
}

// MARK: - Codable

extension TargetDependency {
    private enum Kind: String, Codable {
        case target
        case project
        case framework
        case xcFramework
        case library
        case package
        case sdk
        case cocoapods
        case xctest
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case name
        case target
        case path
        case publicHeaders
        case swiftModuleMap
        case product
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .target:
            let name = try container.decode(String.self, forKey: .name)
            self = .target(name: name)
        case .project:
            let target = try container.decode(String.self, forKey: .target)
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .project(target: target, path: path)
        case .framework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .framework(path: path)
        case .xcFramework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .xcFramework(path: path)
        case .library:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let publicHeaders = try container.decode(AbsolutePath.self, forKey: .publicHeaders)
            let swiftModuleMap = try container.decodeIfPresent(AbsolutePath.self, forKey: .swiftModuleMap)
            self = .library(path: path, publicHeaders: publicHeaders, swiftModuleMap: swiftModuleMap)
        case .package:
            let product = try container.decode(String.self, forKey: .product)
            self = .package(product: product)
        case .sdk:
            let name = try container.decode(String.self, forKey: .name)
            let status = try container.decode(SDKStatus.self, forKey: .status)
            self = .sdk(name: name, status: status)
        case .cocoapods:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .cocoapods(path: path)
        case .xctest:
            self = .xctest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .target(name):
            try container.encode(Kind.target, forKey: .kind)
            try container.encode(name, forKey: .name)
        case let .project(target, path):
            try container.encode(Kind.project, forKey: .kind)
            try container.encode(target, forKey: .target)
            try container.encode(path, forKey: .path)
        case let .framework(path):
            try container.encode(Kind.framework, forKey: .kind)
            try container.encode(path, forKey: .path)
        case let .xcFramework(path):
            try container.encode(Kind.xcFramework, forKey: .kind)
            try container.encode(path, forKey: .path)
        case let .library(path, publicHeaders, swiftModuleMap):
            try container.encode(Kind.library, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(publicHeaders, forKey: .publicHeaders)
            try container.encode(swiftModuleMap, forKey: .swiftModuleMap)
        case let .package(product):
            try container.encode(Kind.package, forKey: .kind)
            try container.encode(product, forKey: .product)
        case let .sdk(name, status):
            try container.encode(Kind.sdk, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(status, forKey: .status)
        case let .cocoapods(path):
            try container.encode(Kind.cocoapods, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .xctest:
            try container.encode(Kind.xctest, forKey: .kind)
        }
    }
}
