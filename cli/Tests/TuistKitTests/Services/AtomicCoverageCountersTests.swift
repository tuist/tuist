import Testing
@testable import TuistKit

struct AtomicCoverageCountersTests {
    @Test
    func addsSettingsThatOnlyResolveWhenXcodeBuildsWithCoverage() {
        #expect(AtomicCoverageCounters.adding(to: ["-scheme", "App"]) == [
            "-scheme", "App",
            "OTHER_SWIFT_FLAGS=$(inherited) $(TUIST_ATOMIC_COVERAGE_OTHER_SWIFT_FLAGS_$(CLANG_COVERAGE_MAPPING))",
            "TUIST_ATOMIC_COVERAGE_OTHER_SWIFT_FLAGS_YES=-Xllvm -instrprof-atomic-counter-update-all",
            "OTHER_CFLAGS=$(inherited) $(TUIST_ATOMIC_COVERAGE_OTHER_CFLAGS_$(CLANG_COVERAGE_MAPPING))",
            "TUIST_ATOMIC_COVERAGE_OTHER_CFLAGS_YES=-fprofile-update=atomic",
        ])
    }

    @Test
    func extendsASettingTheCallerAlreadyOverrides() {
        #expect(AtomicCoverageCounters.adding(to: ["OTHER_SWIFT_FLAGS=-DCI", "-scheme", "App"]) == [
            "OTHER_SWIFT_FLAGS=-DCI $(TUIST_ATOMIC_COVERAGE_OTHER_SWIFT_FLAGS_$(CLANG_COVERAGE_MAPPING))",
            "-scheme", "App",
            "TUIST_ATOMIC_COVERAGE_OTHER_SWIFT_FLAGS_YES=-Xllvm -instrprof-atomic-counter-update-all",
            "OTHER_CFLAGS=$(inherited) $(TUIST_ATOMIC_COVERAGE_OTHER_CFLAGS_$(CLANG_COVERAGE_MAPPING))",
            "TUIST_ATOMIC_COVERAGE_OTHER_CFLAGS_YES=-fprofile-update=atomic",
        ])
    }
}
