import ProjectDescription
import Testing
@testable import TuistLoader

struct SettingsDictionaryMergeTests {
    @Test func merge_inheritFromProject_whenNewArrayContainsInherited_preservesExistingArray() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DSTAGING"])],
            policy: .inheritFromProject
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"])
        )
    }

    @Test func merge_inheritFromProject_whenExistingArrayDoesNotContainInherited_addsInherited() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DSTAGING"])],
            policy: .inheritFromProject
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"])
        )
    }

    @Test func merge_inheritFromProject_whenNewStringContainsInherited_preservesExistingArray() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .string("$(inherited) -DSTAGING")],
            policy: .inheritFromProject
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"])
        )
    }

    @Test func merge_inheritFromProject_whenExistingStringDoesNotContainInherited_addsInherited() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .string("-enable-experimental-feature Lifetimes"),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .string("$(inherited) -DSTAGING")],
            policy: .inheritFromProject
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature Lifetimes"])
        )
    }

    @Test func merge_inheritFromProject_whenTargetHasNoValue_leavesValueAtProjectLevel() {
        var subject: SettingsDictionary = [:]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DSTAGING"])],
            policy: .inheritFromProject
        )

        #expect(subject["OTHER_SWIFT_FLAGS"] == nil)
    }

    @Test func merge_inheritFromProject_whenNewArrayDoesNotContainInherited_overwritesArray() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["-DRELEASE"])],
            policy: .inheritFromProject
        )

        #expect(subject["OTHER_SWIFT_FLAGS"] == .array(["-DRELEASE"]))
    }

    @Test func merge_appendArrays_whenNewArrayDoesNotContainInherited_concatenatesArrays() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["-DSTAGING"])],
            policy: .appendArrays
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes", "-DSTAGING"])
        )
    }

    @Test func merge_appendArrays_preservesInheritedValues() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DSTAGING"])],
            policy: .appendArrays
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes", "$(inherited)", "-DSTAGING"])
        )
    }

    @Test func merge_whenScalarValue_overwritesScalar() {
        var subject: SettingsDictionary = [
            "MACOSX_DEPLOYMENT_TARGET": .string("12.0"),
        ]

        subject.merge(
            ["MACOSX_DEPLOYMENT_TARGET": .string("15.0")],
            policy: .inheritFromProject
        )

        #expect(subject["MACOSX_DEPLOYMENT_TARGET"] == .string("15.0"))
    }
}
