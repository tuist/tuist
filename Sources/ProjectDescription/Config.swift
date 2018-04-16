import Foundation

// MARK: - Config

public class Config {
    public init() {
        dumpIfNeeded(self)
    }
}

// MARK: - Config (JSONConvertible)

extension Config: JSONConvertible {
    func toJSON() -> JSON {
        return .dictionary([:])
    }
}
