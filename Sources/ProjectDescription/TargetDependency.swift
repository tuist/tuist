import Foundation

// MARK: - TargetDependency

public enum TargetDependency {
    case target(name: String)
    case project(target: String, path: String)
    case framework(path: String)
    case library(path: String, publicHeaders: String, swiftModuleMap: String?)
}

// MARK: - TargetDependency (JSONConvertible)

extension TargetDependency: JSONConvertible {
    func toJSON() -> JSON {
        switch self {
        case let .target(name):
            return .dictionary([
                "type": "target".toJSON(),
                "name": name.toJSON(),
            ])
        case let .project(target, path):
            return .dictionary([
                "type": "project".toJSON(),
                "target": target.toJSON(),
                "path": path.toJSON(),
            ])
        case let .framework(path):
            return .dictionary([
                "type": "framework".toJSON(),
                "path": path.toJSON(),
            ])
        case let .library(path, publicHeaders, swiftModuleMap):
            var dictionary: [String: JSON] = [:]
            dictionary["type"] = "library".toJSON()
            dictionary["path"] = path.toJSON()
            dictionary["public_headers"] = publicHeaders.toJSON()
            if let swiftModuleMap = swiftModuleMap {
                dictionary["swift_module_map"] = swiftModuleMap.toJSON()
            }
            return .dictionary(dictionary)
        }
    }
}
