import Path
import TuistCore
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
        public struct PrimaryBundleIcon: Codable, Equatable {
            enum CodingKeys: String, CodingKey {
                case name = "CFBundleIconName"
                case iconFiles = "CFBundleIconFiles"
            }

            public let name: String
            public let iconFiles: [String]

            public init(
                name: String,
                iconFiles: [String]
            ) {
                self.name = name
                self.iconFiles = iconFiles
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                iconFiles = try container.decodeIfPresent([String].self, forKey: .iconFiles) ?? []
            }
        }

        public struct BundleIcons: Codable, Equatable {
            enum CodingKeys: String, CodingKey {
                case primaryIcon = "CFBundlePrimaryIcon"
            }

            /// The app’s primary icon for display on the Home Screen, in the Settings app, and many other places throughout the
            /// system.
            public let primaryIcon: PrimaryBundleIcon?

            public init(
                primaryIcon: PrimaryBundleIcon?
            ) {
                self.primaryIcon = primaryIcon
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                primaryIcon = try container.decodeIfPresent(PrimaryBundleIcon.self, forKey: .primaryIcon)
            }
        }

        /// App version number (e.g. 10.3)
        public let version: Version

        /// Name of the app
        public let name: String

        /// Bundle ID
        public let bundleId: String

        /// Minimum OS version
        public let minimumOSVersion: Version

        /// Supported destination platforms.
        public let supportedPlatforms: [DestinationType]

        /// Information about all of the icons used by the app.
        public let bundleIcons: BundleIcons?

        init(
            version: Version,
            name: String,
            bundleId: String,
            minimumOSVersion: Version,
            supportedPlatforms: [DestinationType],
            bundleIcons: BundleIcons?
        ) {
            self.version = version
            self.name = name
            self.bundleId = bundleId
            self.minimumOSVersion = minimumOSVersion
            self.supportedPlatforms = supportedPlatforms
            self.bundleIcons = bundleIcons
        }

        enum CodingKeys: String, CodingKey {
            case version = "CFBundleShortVersionString"
            case name = "CFBundleName"
            case bundleId = "CFBundleIdentifier"
            case minimumOSVersion = "MinimumOSVersion"
            case supportedPlatforms = "CFBundleSupportedPlatforms"
            case bundleIcons = "CFBundleIcons"
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
                    if let platform = Platform.allCases
                        .first(where: { platformSDK.lowercased() == $0.xcodeDeviceSDK })
                    {
                        return .device(platform)
                    } else if let platform = Platform.allCases
                        .first(where: { platformSDK.lowercased() == $0.xcodeSimulatorSDK })
                    {
                        return .simulator(platform)
                    } else {
                        throw InfoPlistError.unknownPlatform(platform: platformSDK, app: name)
                    }
                }
            bundleIcons = try container.decodeIfPresent(
                BundleIcons.self,
                forKey: .bundleIcons
            )
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
            supportedPlatforms: [DestinationType] = [.simulator(.iOS)],
            bundleIcons: BundleIcons = .test()
        ) -> Self {
            .init(
                version: version,
                name: name,
                bundleId: bundleId,
                minimumOSVersion: minimumOSVersion,
                supportedPlatforms: supportedPlatforms,
                bundleIcons: bundleIcons
            )
        }
    }

    extension AppBundle.InfoPlist.BundleIcons {
        public static func test(
            primaryIcon: AppBundle.InfoPlist.PrimaryBundleIcon = .test()
        ) -> Self {
            .init(
                primaryIcon: primaryIcon
            )
        }
    }

    extension AppBundle.InfoPlist.PrimaryBundleIcon {
        public static func test(
            name: String = "AppIcon",
            iconFiles: [String] = ["AppIcon60x60"]
        ) -> Self {
            .init(
                name: name,
                iconFiles: iconFiles
            )
        }
    }

#endif
