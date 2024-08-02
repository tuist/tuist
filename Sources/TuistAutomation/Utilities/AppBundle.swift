import Path
import TuistSupport
import XcodeGraph

public struct AppBundle: Equatable {
    /// Path to the app bundle
    public let path: AbsolutePath

    /// The app's Info.plist
    public let infoPlist: InfoPlist

    enum InfoPlistError: FatalError {
        case unknownPlatform(platform: String, app: String)

        var description: String {
            switch self {
            case let .unknownPlatform(platform: platform, app: app):
                return "The \(app)'s supported platform \(platform) is unknown."
            }
        }

        var type: ErrorType {
            switch self {
            case .unknownPlatform:
                return .abort
            }
        }
    }

    public struct InfoPlist: Codable, Equatable {
        /// App version number (e.g. 10.3)
        public let version: Version

        /// Name of the app
        public let name: String

        /// Bundle ID
        public let bundleId: String

        /// Minimum OS version
        public let minimumOSVersion: Version

        /// Supported simulator platforms.
        /// Device is currently not supported.
        public let supportedPlatforms: [SupportedPlatform]

        init(
            version: Version,
            name: String,
            bundleId: String,
            minimumOSVersion: Version,
            supportedPlatforms: [SupportedPlatform]
        ) {
            self.version = version
            self.name = name
            self.bundleId = bundleId
            self.minimumOSVersion = minimumOSVersion
            self.supportedPlatforms = supportedPlatforms
        }

        public enum SupportedPlatform: Codable, Equatable {
            case simulator(Platform)
            case device(Platform)
        }

        enum CodingKeys: String, CodingKey {
            case version = "CFBundleShortVersionString"
            case name = "CFBundleName"
            case bundleId = "CFBundleIdentifier"
            case minimumOSVersion = "MinimumOSVersion"
            case supportedPlatforms = "CFBundleSupportedPlatforms"
        }

        public init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<AppBundle.InfoPlist.CodingKeys> = try decoder
                .container(keyedBy: AppBundle.InfoPlist.CodingKeys.self)
            version = Version(
                stringLiteral: try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.version)
            )
            let name = try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.name)
            self.name = name
            bundleId = try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.bundleId)
            minimumOSVersion = Version(
                stringLiteral: try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.minimumOSVersion)
            )
            supportedPlatforms = try container.decode([String].self, forKey: AppBundle.InfoPlist.CodingKeys.supportedPlatforms)
                .map { platformSDK in
                    if let platform = Platform(commandLineValue: platformSDK) {
                        return .device(platform)
                    } else if let platform = Platform.allCases
                        .first(where: { platformSDK.lowercased() == $0.xcodeSimulatorSDK })
                    {
                        return .simulator(platform)
                    } else {
                        throw InfoPlistError.unknownPlatform(platform: platformSDK, app: name)
                    }
                }
        }
    }
}

#if DEBUG
    extension AppBundle {
        public static func test(
            path: AbsolutePath = try! AbsolutePath(validating: "/App.app"), // swiftlint:disable:this force_try
            infoPlist: InfoPlist = .test()
        ) -> Self {
            .init(
                path: path,
                infoPlist: infoPlist
            )
        }
    }

    extension AppBundle.InfoPlist {
        public static func test(
            version: Version = Version("1.0"),
            name: String = "App",
            bundleId: String = "io.tuist.App",
            minimumOSVersion: Version = Version("17.4"),
            supportedPlatforms: [SupportedPlatform] = [.simulator(.iOS)]
        ) -> Self {
            .init(
                version: version,
                name: name,
                bundleId: bundleId,
                minimumOSVersion: minimumOSVersion,
                supportedPlatforms: supportedPlatforms
            )
        }
    }

#endif
