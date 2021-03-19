import Foundation

public enum ProjectOptions: Codable, Equatable, Hashable {
    /// Enables creation of resource interfaces
    case synthesizedResourceAccessors
}

extension ProjectOptions {
    enum CodingKeys: String, CodingKey {
        case synthesizedResourceAccessors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = container.allKeys.first

        switch key {
        case .synthesizedResourceAccessors:
            self = .synthesizedResourceAccessors
            return
        default:
            fatalError("Unrecognized Project Option")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .synthesizedResourceAccessors:
            try container.encode("synthesizedResourceAccessors", forKey: .synthesizedResourceAccessors)
        }
    }
}
