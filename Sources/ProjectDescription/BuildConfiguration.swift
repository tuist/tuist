import Foundation

// MARK: - BuildConfiguration

public enum BuildConfiguration: String {
    case debug
    case release
}

// MARK: - BuildConfiguration (JSONConvertible)

extension BuildConfiguration: JSONConvertible {
    func toJSON() -> JSON {
        return rawValue.toJSON()
    }
}
