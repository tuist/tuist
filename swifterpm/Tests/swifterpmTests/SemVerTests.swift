import Testing
@testable import SwifterPMCore

struct SemVerTests {
    @Test
    func semanticVersionsOrderPrereleasesBeforeReleases() throws {
        #expect(try SemVer("1.2.3-alpha") < SemVer("1.2.3"))
        #expect(try SemVer("1.2.3") < SemVer("1.2.4"))
    }

    @Test
    func semanticVersionsAcceptAbbreviatedCoresAndRejectNonNumericOnes() throws {
        // SwiftPM-compatible: shorter cores normalize zero-extended.
        #expect(try SemVer("1.2").description == "1.2.0")
        #expect(try SemVer("1").description == "1.0.0")
        #expect(try SemVer("0.4") == SemVer("0.4.0"))

        #expect(throws: (any Error).self) {
            try SemVer("one.two.three")
        }
        #expect(throws: (any Error).self) {
            try SemVer("1.2.3.4")
        }
    }

    @Test
    func descriptionPreservesBuildMetadataAndPrerelease() throws {
        // Build metadata must round-trip so a tag like "1.7.3+cio.1" lands in
        // Package.resolved verbatim, matching SwiftPM.
        #expect(try SemVer("1.7.3+cio.1").description == "1.7.3+cio.1")
        #expect(try SemVer("1.2.3").description == "1.2.3")
        #expect(try SemVer("1.2.3-alpha.1").description == "1.2.3-alpha.1")
        #expect(try SemVer("1.0.0-beta.2+build.5").description == "1.0.0-beta.2+build.5")
    }

    @Test
    func buildMetadataParsesIntoItsOwnComponent() throws {
        let version = try SemVer("1.7.3+cio.1")
        #expect(version.major == 1)
        #expect(version.minor == 7)
        #expect(version.patch == 3)
        #expect(version.prerelease == "")
        #expect(version.buildMetadata == "cio.1")

        let plain = try SemVer("1.2.3")
        #expect(plain.buildMetadata == "")
    }

    @Test
    func buildMetadataIsIgnoredForOrderingEqualityAndHashing() throws {
        // Per the SemVer spec, build metadata carries no precedence and does
        // not change version identity, so resolution behavior is unchanged.
        #expect(try SemVer("1.7.3+cio.1") == SemVer("1.7.3"))
        #expect(try !(SemVer("1.7.3+cio.1") < SemVer("1.7.3")))
        #expect(try !(SemVer("1.7.3") < SemVer("1.7.3+cio.1")))
        #expect(try SemVer("1.7.3+cio.1").hashValue == SemVer("1.7.3").hashValue)

        let set: Set<SemVer> = try [SemVer("1.7.3+cio.1"), SemVer("1.7.3")]
        #expect(set.count == 1)
    }

    @Test
    func ascendingForSortBreaksTiesDeterministicallyForBuildMetadataVariants() throws {
        // SemVer's `<` is spec-compliant (ignores build metadata), which makes
        // `sorted(by:<)` unstable for `1.7.3` vs `1.7.3+cio.1`. The tiebreaker
        // sorts the build-metadata variant before the plain version so that
        // `.last` (the picked "latest") is deterministic across runs.
        let plain = try SemVer("1.7.3")
        let withMetadata = try SemVer("1.7.3+cio.1")

        #expect(SemVer.ascendingForSort(withMetadata, plain))
        #expect(!SemVer.ascendingForSort(plain, withMetadata))
        #expect(!SemVer.ascendingForSort(plain, plain))

        let sorted = try [
            SemVer("1.7.3+cio.1"), SemVer("1.7.3"), SemVer("1.7.3+cio.2"),
        ].sorted(by: SemVer.ascendingForSort)
        #expect(sorted.last?.buildMetadata == "")

        // Strictly different versions stay in spec order regardless of metadata.
        #expect(try SemVer.ascendingForSort(SemVer("1.7.3"), SemVer("1.7.4")))
        #expect(try !SemVer.ascendingForSort(SemVer("1.7.4"), SemVer("1.7.3+cio.1")))
    }

    @Test
    func versionRangesMatchExactAndOpenRanges() throws {
        let exact = try VersionRange.singleton(SemVer("1.2.3"))
        #expect(try exact.contains(SemVer("1.2.3")))
        #expect(try !exact.contains(SemVer("1.2.4")))

        let range = try VersionRange.between(SemVer("1.0.0"), SemVer("2.0.0"))
        #expect(try range.contains(SemVer("1.5.0")))
        #expect(try !range.contains(SemVer("2.0.0")))
    }
}
