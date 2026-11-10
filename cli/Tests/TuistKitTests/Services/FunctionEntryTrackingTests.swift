import Testing
@testable import TuistKit

struct FunctionEntryTrackingTests {
    @Test func reachesTheFlagsThroughOneVariablePerTarget() {
        #expect(FunctionEntryTracking.adding(to: ["-quiet"], targets: ["Core", "CoreTests"]) == [
            "-quiet",
            "OTHER_SWIFT_FLAGS=$(inherited) $(TUIST_FUNCTION_TRACKING_$(CLANG_COVERAGE_MAPPING)_$(TARGET_NAME:c99extidentifier))",
            "TUIST_FUNCTION_TRACKING_YES_Core=-sanitize=undefined -sanitize-coverage=func,trace-pc-guard,pc-table",
            "TUIST_FUNCTION_TRACKING_YES_CoreTests=-sanitize=undefined -sanitize-coverage=func,trace-pc-guard,pc-table",
        ])
    }

    @Test func extendsTheSwiftFlagsTheCallerPasses() {
        #expect(FunctionEntryTracking.adding(to: ["OTHER_SWIFT_FLAGS=-DX"], targets: ["Core"]) == [
            "OTHER_SWIFT_FLAGS=-DX $(TUIST_FUNCTION_TRACKING_$(CLANG_COVERAGE_MAPPING)_$(TARGET_NAME:c99extidentifier))",
            "TUIST_FUNCTION_TRACKING_YES_Core=-sanitize=undefined -sanitize-coverage=func,trace-pc-guard,pc-table",
        ])
    }

    @Test func addsNothingWithoutTargets() {
        #expect(FunctionEntryTracking.adding(to: ["-quiet"], targets: []) == ["-quiet"])
    }
}
