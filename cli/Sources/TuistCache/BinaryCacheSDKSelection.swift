import TuistCore

/// Selects outputs without changing the compilation identities computed from the original graph.
public enum BinaryCacheSDKSelection: Equatable {
    case all
    case simulators
    case devices
    case variant(BinaryCacheVariant)

    public func fingerprints(_ fingerprints: [String: String]) -> [String: String] {
        switch self {
        case .all:
            return fingerprints
        case .simulators:
            return fingerprints
                .filter { $0.key != BinaryCacheVariant.iosDevice.rawValue && $0.key != BinaryCacheVariant.catalyst.rawValue }
        case .devices:
            return fingerprints
                .filter { $0.key == BinaryCacheVariant.iosDevice.rawValue || $0.key == BinaryCacheVariant.macos.rawValue }
        case let .variant(variant):
            if fingerprints.keys.allSatisfy({ $0 == BinaryCacheVariant.macos.rawValue }) { return fingerprints }
            return fingerprints.filter { $0.key == variant.rawValue }
        }
    }

    public func includes(_ variant: BinaryCacheVariant) -> Bool {
        switch self {
        case .all: true
        case .simulators: variant == .iosSimulator || variant == .macos
        case .devices: variant == .iosDevice || variant == .macos
        case let .variant(selected): selected == variant
        }
    }
}
