import Foundation
import TSCBasic

public enum FrameworkStatus: String, Codable {
    case required
    case optional
}

public enum SDKStatus: String, Codable {
    case required
    case optional
}

public enum PodDependencyType: String, Codable {
    case library
    case framework
}

public enum TargetDependency: Equatable, Hashable, Codable {
    public enum PackageType: String, Equatable, Hashable, Codable {
        case runtime
        case plugin
        case macro
    }

    public struct Condition: Codable, Hashable, Equatable, Comparable {
        public static func < (lhs: TargetDependency.Condition, rhs: TargetDependency.Condition) -> Bool {
            lhs.platformFilters < rhs.platformFilters
        }

        public let platformFilters: PlatformFilters
        private init(platformFilters: PlatformFilters) {
            self.platformFilters = platformFilters
        }

        public static func when(_ platformFilters: Set<PlatformFilter>) -> Condition? {
            guard !platformFilters.isEmpty else { return nil }
            return Condition(platformFilters: platformFilters)
        }

        public func intersection(_ other: Condition?) -> CombinationResult {
            guard let otherFilters = other?.platformFilters else { return .condition(self) }
            let filters = platformFilters.intersection(otherFilters)

            if filters.isEmpty {
                return .incompatible
            } else {
                return .condition(Condition(platformFilters: filters))
            }
        }

        public func union(_ other: Condition?) -> CombinationResult {
            guard let otherFilters = other?.platformFilters else { return .condition(nil) }
            let filters = platformFilters.union(otherFilters)

            if filters.isEmpty {
                return .condition(nil)
            } else {
                return .condition(Condition(platformFilters: filters))
            }
        }

        public enum CombinationResult: Equatable {
            case incompatible
            case condition(Condition?)

            public func combineWith(_ other: CombinationResult) -> CombinationResult {
                switch (self, other) {
                case (.incompatible, .incompatible):
                    return .incompatible
                case (_, .incompatible):
                    return self
                case (.incompatible, _):
                    return other
                case let (.condition(lhs), .condition(rhs)):
                    guard let lhs, let rhs else { return .condition(nil) }
                    return lhs.union(rhs)
                }
            }
        }
    }

    case target(name: String, condition: Condition? = nil)
    case project(target: String, path: AbsolutePath, condition: Condition? = nil)
    case framework(path: AbsolutePath, status: FrameworkStatus, condition: Condition? = nil)
    case xcframework(path: AbsolutePath, status: FrameworkStatus, condition: Condition? = nil)
    case library(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?,
        condition: Condition? = nil
    )
    case package(product: String, type: PackageType, condition: Condition? = nil)
    case sdk(name: String, status: SDKStatus, condition: Condition? = nil)
    case cocoapod(type: PodDependencyType, content: String)
    case xctest

    public var condition: Condition? {
        switch self {
        case .target(name: _, condition: let condition):
            condition
        case .project(target: _, path: _, condition: let condition):
            condition
        case .framework(path: _, status: _, condition: let condition):
            condition
        case .xcframework(path: _, status: _, condition: let condition):
            condition
        case .library(path: _, publicHeaders: _, swiftModuleMap: _, condition: let condition):
            condition
        case .package(product: _, type: _, condition: let condition):
            condition
        case .sdk(name: _, status: _, condition: let condition):
            condition
        case .xctest, .cocoapod: nil
        }
    }

    public func withCondition(_ condition: Condition?) -> TargetDependency {
        switch self {
        case .target(name: let name, condition: _):
            return .target(name: name, condition: condition)
        case .project(target: let target, path: let path, condition: _):
            return .project(target: target, path: path, condition: condition)
        case .framework(path: let path, status: let status, condition: _):
            return .framework(path: path, status: status, condition: condition)
        case .xcframework(path: let path, status: let status, condition: _):
            return .xcframework(path: path, status: status, condition: condition)
        case .library(path: let path, publicHeaders: let headers, swiftModuleMap: let moduleMap, condition: _):
            return .library(path: path, publicHeaders: headers, swiftModuleMap: moduleMap, condition: condition)
        case .package(product: let product, type: let type, condition: _):
            return .package(product: product, type: type, condition: condition)
        case .sdk(name: let name, status: let status, condition: _):
            return .sdk(name: name, status: status, condition: condition)
        case .xctest: return .xctest
        case .cocoapod: return self
        }
    }
}
