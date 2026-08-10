import ProjectDescription
import Testing
@testable import TuistLoader

struct SettingsDictionaryMergeTests {
    @Test func merge_replaceUnlessInherited_whenNewArrayContainsInherited_concatenatesArrays() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DSTAGING"])],
            arrayMergePolicy: .replaceUnlessInherited
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes", "-DSTAGING"])
        )
    }

    @Test func merge_replaceUnlessInherited_whenNewArrayDoesNotContainInherited_overwritesArray() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["-DRELEASE"])],
            arrayMergePolicy: .replaceUnlessInherited
        )

        #expect(subject["OTHER_SWIFT_FLAGS"] == .array(["-DRELEASE"]))
    }

    @Test func merge_append_whenNewArrayDoesNotContainInherited_concatenatesArrays() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["-DSTAGING"])],
            arrayMergePolicy: .append
        )

        #expect(
            subject["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes", "-DSTAGING"])
        )
    }

    @Test func merge_append_preservesInheritedValues() {
        var subject: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-enable-experimental-feature", "Lifetimes"]),
        ]

        subject.merge(
            ["OTHER_SWIFT_FLAGS": .array(["$(inherited)", "-DSTAGING"])],
            arrayMergePolicy: .append
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
            arrayMergePolicy: .replaceUnlessInherited
        )

        #expect(subject["MACOSX_DEPLOYMENT_TARGET"] == .string("15.0"))
    }
}
