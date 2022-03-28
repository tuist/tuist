import TSCUtility

extension Version {
    /// Create a version object from string.
    /// It does not have to be formatted to SPM's standards (i.e. minor and patch versions can be omitted if zero)
    /// - Parameters:
    ///   - unformattedString: The string to parse.
    public init?(unformattedString: String) {
        let versionComponents = unformattedString.split(separator: ".")

        guard 1 ... 3 ~= versionComponents.count else { return nil }

        let formattedVersionComponents = versionComponents + (versionComponents.count ..< 3).map { _ in "0" }

        self.init(formattedVersionComponents.joined(separator: "."))
    }

    public var xcodeStringValue: String {
        "\(major)\(minor)\(patch)"
    }
}
