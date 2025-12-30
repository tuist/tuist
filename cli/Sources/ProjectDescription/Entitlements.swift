// MARK: - Entitlements

public enum Entitlements: Codable, Equatable, Sendable {
    /// The path to an existing .entitlements file.
    case file(path: Path)

    /// A dictionary with the entitlements content. Tuist generates the .entitlements file at the generation time.
    case dictionary([String: Plist.Value])

    /// A build setting variable that points to an .entitlements file.
    ///
    /// This should be used when you have an xcconfig file or build setting that defines a variable pointing to the entitlements
    /// file path.
    /// This is particularly useful when the project has different entitlements files per configuration (e.g., debug, release,
    /// staging).
    ///
    /// Example:
    ///
    /// ```
    /// .target(
    ///     ...
    ///     entitlements: .variable("$(ENTITLEMENT_FILE_VARIABLE)")
    /// )
    /// ```
    ///
    /// Or, as literal string:
    ///
    /// ```
    /// .target(
    ///     ...
    ///     entitlements: "$(ENTITLEMENT_FILE_VARIABLE)"
    /// )
    /// ```
    ///
    /// > Note: For per-configuration entitlements, you can also:
    /// > 1. Keep `Target.entitlements` as `nil`
    /// > 2. Set the `CODE_SIGN_ENTITLEMENTS` build setting using `Target.settings` for each configuration
    /// > 3. If you want the entitlement files to be included in the project navigator, add them using `Project.additionalFiles`
    /// >
    /// > Example:
    /// > ```swift
    /// > let target = Target(
    /// >     name: "MyApp",
    /// >     // ... other properties
    /// >     entitlements: nil, // Important: keep this as nil
    /// >     settings: .settings(
    /// >         configurations: [
    /// >             .debug(name: "Debug", settings: ["CODE_SIGN_ENTITLEMENTS": "Debug.entitlements"]),
    /// >             .release(name: "Release", settings: ["CODE_SIGN_ENTITLEMENTS": "Release.entitlements"])
    /// >         ]
    /// >     )
    /// > )
    /// >
    /// > let project = Project(
    /// >     name: "MyProject",
    /// >     targets: [target],
    /// >     additionalFiles: [
    /// >         "Debug.entitlements",
    /// >         "Release.entitlements"
    /// >     ]
    /// > )
    /// > ```
    case variable(String)

    // MARK: - Error

    public enum CodingError: Error {
        case invalidType(String)
    }

    // MARK: - Internal

    public var path: Path? {
        switch self {
        case let .file(path):
            return path
        default:
            return nil
        }
    }
}

// MARK: - Entitlements - ExpressibleByStringInterpolation

extension Entitlements: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        if value.hasPrefix("$(") {
            self = .variable(value)
        } else {
            self = .file(path: .path(value))
        }
    }
}
