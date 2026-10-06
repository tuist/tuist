import Testing
import XcodeGraph
@testable import TuistKit

struct SwiftWarningFlagsDeduplicationTests {
    @Test(arguments: ["-Werror", "-Wwarning"])
    func deduplicatesRepeatedFrontendWarningSequences(flag: String) {
        let flags = ["-Xfrontend", flag, "-Xfrontend", "ExistentialAny"]
        let settings: SettingsDictionary = ["OTHER_SWIFT_FLAGS": .array(flags + flags)]

        #expect(settings.removeOtherSwiftFlagsDuplicates() == ["OTHER_SWIFT_FLAGS": .array(flags)])
    }

    @Test(arguments: ["-Werror", "-Wwarning"])
    func preservesWarningSeverityOrder(flag: String) {
        let oppositeFlag = flag == "-Werror" ? "-Wwarning" : "-Werror"
        let settings: SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": .array([
                flag, "ExistentialAny",
                oppositeFlag, "ExistentialAny",
                flag, "ExistentialAny",
            ]),
        ]

        #expect(settings.removeOtherSwiftFlagsDuplicates() == settings)
    }

    @Test(arguments: ["OTHER_SWIFT_FLAGS", "OTHER_SWIFT_FLAGS[sdk=iphoneos*]"])
    func preservesForwardedWarningFlags(key: String) {
        let settings: SettingsDictionary = [
            key: .array([
                "-Xcc", "-Werror",
                "-DDEBUG",
                "-Xcc", "-Werror",
                "-DDEBUG",
                "-Werror", "ExistentialAny",
                "-Werror", "UnknownWarningGroup",
            ]),
        ]

        #expect(settings.removeOtherSwiftFlagsDuplicates() == [
            key: .array([
                "-Xcc", "-Werror",
                "-DDEBUG",
                "-Werror", "ExistentialAny",
                "-Werror", "UnknownWarningGroup",
            ]),
        ])
    }

    @Test(arguments: ["OTHER_SWIFT_FLAGS", "OTHER_SWIFT_FLAGS[sdk=iphoneos*]"])
    func preservesWarningGroups(key: String) {
        let settings: SettingsDictionary = [
            key: .array([
                "$(inherited)",
                "-Werror", "ExistentialAny",
                "-Werror", "UnknownWarningGroup",
                "-Werror", "DeprecatedDeclaration",
                "-Werror", "ExistentialAny",
                "-Wwarning", "ExistentialAny",
                "-Wwarning", "UnknownWarningGroup",
                "-Wwarning", "DeprecatedDeclaration",
                "-Wwarning", "ExistentialAny",
                "-warnings-as-errors", "-warnings-as-errors",
                "-Werror=StrictMemorySafety", "-Werror=StrictMemorySafety",
            ]),
        ]

        #expect(settings.removeOtherSwiftFlagsDuplicates() == [
            key: .array([
                "$(inherited)",
                "-Werror", "ExistentialAny",
                "-Werror", "UnknownWarningGroup",
                "-Werror", "DeprecatedDeclaration",
                "-Werror", "ExistentialAny",
                "-Wwarning", "ExistentialAny",
                "-Wwarning", "UnknownWarningGroup",
                "-Wwarning", "DeprecatedDeclaration",
                "-Wwarning", "ExistentialAny",
                "-warnings-as-errors",
                "-Werror=StrictMemorySafety",
            ]),
        ])
    }
}
