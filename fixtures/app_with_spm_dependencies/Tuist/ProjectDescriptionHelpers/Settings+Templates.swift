import Foundation
import ProjectDescription

extension ProjectDescription.Settings {
    public static var projectSettings: Self {
        .settings(
            configurations: BuildEnvironment.allCases.map(\.projectConfiguration)
        )
    }

    public static var targetSettings: Self {
        .settings(
            base: [
                "SOME_BASE_FLAG": .string("VALUE"),
                "OTHER_LDFLAGS": .string("-ObjC"),
            ].otherSwiftFlags("-enable-actor-data-race-checks"),
            configurations: BuildEnvironment.allCases.map(\.targetConfiguration)
        )
    }
}
