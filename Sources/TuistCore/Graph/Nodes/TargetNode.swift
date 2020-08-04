import Foundation
import TSCBasic
import TuistSupport

public class TargetNode: GraphNode {
    // MARK: - Attributes

    public let project: Project
    public let target: Target
    public var dependencies: [GraphNode]

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case platform
        case product
        case bundleId = "bundle_id"
        case dependencies
        case type
    }

    // MARK: - Init

    public init(project: Project,
                target: Target,
                dependencies: [GraphNode])
    {
        self.project = project
        self.target = target
        self.dependencies = dependencies
        super.init(path: project.path, name: target.name)
    }

    // MARK: - Hashable

    override public func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(target.name)
    }

    // MARK: - Equatable

    static func == (lhs: TargetNode, rhs: TargetNode) -> Bool {
        lhs.isEqual(to: rhs) && rhs.isEqual(to: lhs)
    }

    override func isEqual(to otherNode: GraphNode) -> Bool {
        guard let otherTagetNode = otherNode as? TargetNode else {
            return false
        }
        return path == otherTagetNode.path
            && name == otherTagetNode.name
    }

    // MARK: - Encodable

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(target.name, forKey: .name)
        try container.encode(target.platform.rawValue, forKey: .platform)
        try container.encode(target.product.rawValue, forKey: .product)
        try container.encode(target.bundleId, forKey: .bundleId)
        try container.encode("source", forKey: .type)

        let dependencies = self.dependencies.compactMap { (dependency) -> String? in
            if let targetDependency = dependency as? TargetNode {
                return targetDependency.target.name
            } else if let precompiledDependency = dependency as? PrecompiledNode {
                return precompiledDependency.name
            } else if let cocoapodsDependency = dependency as? CocoaPodsNode {
                return cocoapodsDependency.name
            } else {
                return nil
            }
        }
        try container.encode(dependencies, forKey: .dependencies)
    }

    // MARK: - Helpers

    public var targetDependencies: [TargetNode] {
        dependencies.lazy.compactMap { $0 as? TargetNode }
    }

    public var precompiledDependencies: [PrecompiledNode] {
        dependencies.lazy.compactMap { $0 as? PrecompiledNode }
    }

    public var packages: [PackageProductNode] {
        dependencies.lazy.compactMap { $0 as? PackageProductNode }
    }

    public var libraryDependencies: [LibraryNode] {
        dependencies.lazy.compactMap { $0 as? LibraryNode }
    }

    public var frameworkDependencies: [FrameworkNode] {
        dependencies.lazy.compactMap { $0 as? FrameworkNode }
    }

    public var sdkDependencies: [SDKNode] {
        dependencies.lazy.compactMap { $0 as? SDKNode }
    }

    /// Returns true if the target depends on XCTest
    public var dependsOnXCTest: Bool {
        sdkDependencies.contains(where: { $0.name == "XCTest" })
    }
}
