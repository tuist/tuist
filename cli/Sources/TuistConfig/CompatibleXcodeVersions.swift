import Foundation

#if os(macOS)
    import XcodeGraph
#endif

public enum CompatibleXcodeVersions: Equatable, Hashable, ExpressibleByArrayLiteral, ExpressibleByStringInterpolation,
    CustomStringConvertible
{
    case all

    #if os(macOS)
        case exact(Version)
        case upToNextMajor(Version)
        case upToNextMinor(Version)
    #endif

    case list([CompatibleXcodeVersions])

    #if os(macOS)
        public func isCompatible(versionString: String) -> Bool {
            let xCodeVersion: Version = "\(versionString)"

            switch self {
            case .all:
                return true
            case let .exact(version):
                return version == xCodeVersion
            case let .upToNextMajor(version):
                return xCodeVersion.major == version.major && xCodeVersion >= version
            case let .upToNextMinor(version):
                return version.major == xCodeVersion.major && version.minor == xCodeVersion.minor
                    && xCodeVersion >= version
            case let .list(versions):
                return versions.contains { $0.isCompatible(versionString: versionString) }
            }
        }
    #endif

    public init(stringLiteral value: String) {
        #if os(macOS)
            self = .exact(Version(stringLiteral: value))
        #else
            self = .all
        #endif
    }

    public init(arrayLiteral elements: [CompatibleXcodeVersions]) {
        self = .list(elements)
    }

    public init(arrayLiteral elements: CompatibleXcodeVersions...) {
        self = .list(elements)
    }

    public var description: String {
        switch self {
        case .all:
            return "all"
        #if os(macOS)
            case let .exact(version):
                return "\(version)"
            case let .upToNextMajor(version):
                return "\(version)..<\(version.major + 1).0.0"
            case let .upToNextMinor(version):
                return "\(version)..<\(version.major).\(version.minor + 1).0"
        #endif
        case let .list(versions):
            return "\(versions.map(\.description).joined(separator: " or "))"
        }
    }
}
