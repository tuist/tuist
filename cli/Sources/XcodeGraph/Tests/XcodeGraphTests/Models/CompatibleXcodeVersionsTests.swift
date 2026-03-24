import Foundation
import Testing
@testable import XcodeGraph

struct CompatibleXcodeVersionsTests {
    @Test func isCompatible_when_all() {
        // Given
        let subject = CompatibleXcodeVersions.all

        // Then
        #expect(subject.isCompatible(versionString: "1"))
        #expect(subject.isCompatible(versionString: "5.5"))
        #expect(subject.isCompatible(versionString: "15.10.10"))
    }

    @Test func isCompatible_when_list() {
        // Given
        let subject = CompatibleXcodeVersions.list([.upToNextMajor("13.2.2"), .upToNextMinor("1"), "12.5.1"])

        // Then
        #expect(subject.isCompatible(versionString: "12.5.1"))
        #expect(!subject.isCompatible(versionString: "12.5.2"))
        #expect(!subject.isCompatible(versionString: "13.2.1"))
        #expect(subject.isCompatible(versionString: "13.2.2"))
        #expect(subject.isCompatible(versionString: "13.3.6"))
        #expect(!subject.isCompatible(versionString: "14.2.0"))
        #expect(subject.isCompatible(versionString: "1.0.0"))
        #expect(subject.isCompatible(versionString: "1.0.5"))
        #expect(!subject.isCompatible(versionString: "2.0.0"))
    }

    @Test func isCompatible_when_exact() {
        // Given
        let subject = CompatibleXcodeVersions.exact("13.2")

        // Then
        #expect(subject.isCompatible(versionString: "13.2"))
        #expect(subject.isCompatible(versionString: "13.2.0"))
        #expect(!subject.isCompatible(versionString: "13.2.2"))
        #expect(!subject.isCompatible(versionString: "13.3.0"))
        #expect(!subject.isCompatible(versionString: "14.2.0"))
    }

    @Test func isCompatible_when_upToNextMajor() {
        // Given
        let subject = CompatibleXcodeVersions.upToNextMajor("13.2")

        // Then
        #expect(!subject.isCompatible(versionString: "12.3.0"))
        #expect(!subject.isCompatible(versionString: "13.0.0"))
        #expect(subject.isCompatible(versionString: "13.2"))
        #expect(subject.isCompatible(versionString: "13.2.0"))
        #expect(subject.isCompatible(versionString: "13.2.2"))
        #expect(subject.isCompatible(versionString: "13.3.0"))
        #expect(!subject.isCompatible(versionString: "14.0.0"))
        #expect(!subject.isCompatible(versionString: "14.2.0"))
    }

    @Test func isCompatible_when_upToNextMinor() {
        // Given
        let subject = CompatibleXcodeVersions.upToNextMinor("13.2")

        // Then
        #expect(!subject.isCompatible(versionString: "12.2.0"))
        #expect(!subject.isCompatible(versionString: "13.0.0"))
        #expect(subject.isCompatible(versionString: "13.2"))
        #expect(subject.isCompatible(versionString: "13.2.0"))
        #expect(subject.isCompatible(versionString: "13.2.2"))
        #expect(!subject.isCompatible(versionString: "13.3.0"))
        #expect(!subject.isCompatible(versionString: "14.2.0"))
    }

    @Test func description() {
        #expect("\(CompatibleXcodeVersions.all)" == "all")
        #expect("\(CompatibleXcodeVersions.exact("1.2"))" == "1.2.0")
        #expect("\(CompatibleXcodeVersions.upToNextMajor("1.2.3"))" == "1.2.3..<2.0.0")
        #expect("\(CompatibleXcodeVersions.upToNextMinor("1.2.3"))" == "1.2.3..<1.3.0")

        let versionsList = CompatibleXcodeVersions.list([.upToNextMajor("13.2.2"), .upToNextMinor("1"), "12.5.1"])
        #expect("\(versionsList)" == "13.2.2..<14.0.0 or 1.0.0..<1.1.0 or 12.5.1")
    }
}
