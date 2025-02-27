// MARK: - Entitlements

public enum Entitlements: Codable, Equatable, Sendable {
    /// The path to an existing .entitlements file.
    case file(path: Path)

    /// A dictionary with the entitlements content. Tuist generates the .entitlements file at the generation time.
    case dictionary([String: Plist.Value])

    /**
      A user defined xcconfig variable map to .entitlements file.

      This should be used when the project has different entitlements files per config (aka: debug,release,staging,etc)

       ````
      .target(
          ...
          entitlements: .variable("$(ENTITLEMENT_FILE_VARIABLE)"),
      )
       ````

      Or as literal string
      ````
     .target(
         ...
         entitlements: $(ENTITLEMENT_FILE_VARIABLE),
     )
      ````
      */
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
