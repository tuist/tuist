public enum CacheTechnology: String, Sendable {
    case `default` = "default"
    case kura = "kura"

    var queryValue: Operations.getCacheEndpoints.Input.Query.technologyPayload? {
        switch self {
        case .default:
            nil
        case .kura:
            .kura
        }
    }
}
