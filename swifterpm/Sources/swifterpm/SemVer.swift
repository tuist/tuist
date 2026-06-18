import Foundation

struct SemVer: Hashable, Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String
    // Preserved so a version string with build metadata (e.g. "1.7.3+cio.1")
    // round-trips verbatim, but excluded from precedence and equality per the
    // SemVer spec: build metadata must not affect ordering or version identity.
    let buildMetadata: String

    init(_ string: String) throws {
        let buildSplit = string.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let withoutBuild = buildSplit[0]
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".")
        // SwiftPM tolerates 1- and 2-component version tags (e.g. swift-subprocess ships `0.4`)
        // and treats missing components as zero. Mirror that to stay compatible with packages
        // that pin or expose abbreviated tags.
        guard (1...3).contains(core.count),
              let major = Int(core[0]),
              core.count < 2 || Int(core[1]) != nil,
              core.count < 3 || Int(core[2]) != nil
        else {
            throw ToolError.message("invalid semantic version: \(string)")
        }
        self.major = major
        self.minor = core.count >= 2 ? Int(core[1])! : 0
        self.patch = core.count >= 3 ? Int(core[2])! : 0
        self.prerelease = parts.count > 1 ? String(parts[1]) : ""
        self.buildMetadata = buildSplit.count > 1 ? String(buildSplit[1]) : ""
    }

    init(major: Int, minor: Int, patch: Int, prerelease: String = "", buildMetadata: String = "") {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    var description: String {
        var result = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty { result += "-\(prerelease)" }
        if !buildMetadata.isEmpty { result += "+\(buildMetadata)" }
        return result
    }

    static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty && !rhs.prerelease.isEmpty { return false }
        if !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return true }
        return lhs.prerelease < rhs.prerelease
    }

    /// Ascending sort with a deterministic tiebreaker for versions that are
    /// `==` under the SemVer spec but differ in build metadata. Build-metadata
    /// variants sort before the plain version so picking `.last`/`max` returns
    /// the plain form, matching SwiftPM's reproducible-resolve behavior.
    static func ascendingForSort(_ lhs: SemVer, _ rhs: SemVer) -> Bool {
        if lhs < rhs { return true }
        if rhs < lhs { return false }
        return !lhs.buildMetadata.isEmpty && rhs.buildMetadata.isEmpty
    }
}

struct VersionRange: Equatable, Sendable {
    let lower: SemVer
    let upper: SemVer
    let exact: Bool

    static func singleton(_ version: SemVer) -> VersionRange {
        VersionRange(lower: version, upper: version, exact: true)
    }

    static func between(_ lower: SemVer, _ upper: SemVer) -> VersionRange {
        VersionRange(lower: lower, upper: upper, exact: false)
    }

    func contains(_ version: SemVer) -> Bool {
        if exact {
            return version == lower
        }
        return version >= lower && version < upper
    }
}
