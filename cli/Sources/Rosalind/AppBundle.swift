import Path

struct AppBundle: Equatable {
    /// Path to the app bundle
    let path: AbsolutePath

    /// The app's Info.plist
    let infoPlist: InfoPlist

    struct InfoPlist: Decodable, Equatable {
        /// App version number (e.g. 10.3)
        let version: String

        /// Name of the app
        let name: String

        /// Bundle ID
        let bundleId: String

        /// Minimum OS version
        let minimumOSVersion: String

        /// Supported destination platforms.
        let supportedPlatforms: [String]

        init(
            version: String,
            name: String,
            bundleId: String,
            minimumOSVersion: String,
            supportedPlatforms: [String]
        ) {
            self.version = version
            self.name = name
            self.bundleId = bundleId
            self.minimumOSVersion = minimumOSVersion
            self.supportedPlatforms = supportedPlatforms
        }

        enum CodingKeys: String, CodingKey {
            case version = "CFBundleShortVersionString"
            case name = "CFBundleName"
            case bundleId = "CFBundleIdentifier"
            case minimumOSVersion = "MinimumOSVersion"
            case minimumSystemVersion = "LSMinimumSystemVersion"
            case supportedPlatforms = "CFBundleSupportedPlatforms"
        }

        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<AppBundle.InfoPlist.CodingKeys> = try decoder
                .container(keyedBy: AppBundle.InfoPlist.CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            name = try container.decode(String.self, forKey: .name)
            bundleId = try container.decode(String.self, forKey: .bundleId)
            // iOS/tvOS/watchOS/visionOS use MinimumOSVersion, macOS uses LSMinimumSystemVersion
            minimumOSVersion = try container.decodeIfPresent(String.self, forKey: .minimumOSVersion)
                ?? container.decode(String.self, forKey: .minimumSystemVersion)
            supportedPlatforms = try container.decode([String].self, forKey: .supportedPlatforms)
        }
    }
}

#if DEBUG
    extension AppBundle {
        static func test(
            // swiftlint:disable:next force_try
            path: AbsolutePath = try! AbsolutePath(validating: "/App.app"),
            infoPlist: AppBundle.InfoPlist = .test()
        ) -> AppBundle {
            AppBundle(
                path: path,
                infoPlist: infoPlist
            )
        }
    }

    extension AppBundle.InfoPlist {
        static func test(
            version: String = "1.0",
            name: String = "App",
            bundleId: String = "com.App",
            minimumOSVersion: String = "18.0",
            supportedPlatforms: [String] = ["iPhoneOS"]
        ) -> AppBundle.InfoPlist {
            AppBundle.InfoPlist(
                version: version,
                name: name,
                bundleId: bundleId,
                minimumOSVersion: minimumOSVersion,
                supportedPlatforms: supportedPlatforms
            )
        }
    }
#endif
