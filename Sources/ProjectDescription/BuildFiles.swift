import Foundation

// MARK: - BuildFiles

public enum BuildFiles {
    case include([String])
    case exclude([String])
}

// MARK: - BuildFiles (JSONConvertible)

extension BuildFiles: JSONConvertible {
    func toJSON() -> JSON {
        switch self {
        case let .include(paths):
            return .dictionary([
                "type": .string("include"),
                "paths": .array(paths.map({ JSON.string($0) })),
            ])
        case let .exclude(paths):
            return .dictionary([
                "type": .string("exclude"),
                "paths": .array(paths.map({ JSON.string($0) })),
            ])
        }
    }
}
