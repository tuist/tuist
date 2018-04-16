import Foundation

// MARK: - Project

public class Project {
    public let name: String
    public let schemes: [Scheme]
    public let targets: [Target]
    public let settings: Settings?
    public let config: String?

    public init(name: String,
                schemes: [Scheme] = [],
                targets: [Target] = [],
                settings: Settings? = nil,
                config: String? = nil) {
        self.name = name
        self.schemes = schemes
        self.targets = targets
        self.settings = settings
        self.config = config
        dumpIfNeeded(self)
    }
}

// MARK: - Project (JSONConvertible)

extension Project: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["name"] = name.toJSON()
        dictionary["schemes"] = schemes.toJSON()
        dictionary["targets"] = targets.toJSON()
        if let settings = settings {
            dictionary["settings"] = settings.toJSON()
        }
        if let config = config {
            dictionary["config"] = config.toJSON()
        }
        return .dictionary(dictionary)
    }
}
