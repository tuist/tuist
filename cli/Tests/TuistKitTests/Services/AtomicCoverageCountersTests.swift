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
            "OTHER_CPLUSPLUSFLAGS=$(inherited) $(TUIST_ATOMIC_COVERAGE_OTHER_CPLUSPLUSFLAGS_$(CLANG_COVERAGE_MAPPING))",
            "TUIST_ATOMIC_COVERAGE_OTHER_CPLUSPLUSFLAGS_YES=-fprofile-update=atomic",
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
            "OTHER_CPLUSPLUSFLAGS=$(inherited) $(TUIST_ATOMIC_COVERAGE_OTHER_CPLUSPLUSFLAGS_$(CLANG_COVERAGE_MAPPING))",
            "TUIST_ATOMIC_COVERAGE_OTHER_CPLUSPLUSFLAGS_YES=-fprofile-update=atomic",
        ])
    }

    @Test
    func extendsCPlusPlusFlagsTheCallerOverrides() {
        let got = AtomicCoverageCounters.adding(to: ["OTHER_CPLUSPLUSFLAGS=-std=c++17 -DCUSTOM_CPP=1"])
        #expect(got
            .first ==
            "OTHER_CPLUSPLUSFLAGS=-std=c++17 -DCUSTOM_CPP=1 $(TUIST_ATOMIC_COVERAGE_OTHER_CPLUSPLUSFLAGS_$(CLANG_COVERAGE_MAPPING))")
    }
}
