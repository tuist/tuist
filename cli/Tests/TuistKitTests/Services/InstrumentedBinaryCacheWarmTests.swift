import Foundation
import Testing

@testable import TuistKit

struct InstrumentedBinaryCacheWarmTests {
    @Test func sourceRoots_addTheOtherSpellingOfPrivateDirectories() {
        #expect(InstrumentedBinaryCacheWarm.sourceRoots(["/private/tmp/checkout", "/tmp/checkout"]) == [
            "/private/tmp/checkout", "/tmp/checkout",
        ])
        #expect(InstrumentedBinaryCacheWarm.sourceRoots(["/var/folders/x/checkout"]) == [
            "/var/folders/x/checkout", "/private/var/folders/x/checkout",
        ])
        #expect(InstrumentedBinaryCacheWarm.sourceRoots(["/Users/ci/checkout", "/Volumes/ci/checkout"]) == [
            "/Users/ci/checkout", "/Volumes/ci/checkout",
        ])
    }

    @Test func buildSettings_instrumentMarkedTargetsAndMapEverySpellingOfTheRoot() {
        let got = InstrumentedBinaryCacheWarm.buildSettings(sourceRoots: ["/tmp/checkout", "/private/tmp/checkout"])

        #expect(got == [
            "CLANG_COVERAGE_MAPPING=$(TUIST_BINARY_CACHE_COVERAGE_MAPPING_$(TUIST_BINARY_CACHE_COVERAGE))",
            "TUIST_BINARY_CACHE_COVERAGE_MAPPING_=NO",
            "TUIST_BINARY_CACHE_COVERAGE_MAPPING_YES=YES",
            "OTHER_SWIFT_FLAGS=$(inherited) $(TUIST_BINARY_CACHE_COVERAGE_SWIFT_FLAGS_$(TUIST_BINARY_CACHE_COVERAGE))",
            "TUIST_BINARY_CACHE_COVERAGE_SWIFT_FLAGS_YES=-Xllvm -instrprof-atomic-counter-update-all "
                + "-coverage-prefix-map /tmp/checkout=/TUIST_SOURCE_ROOT "
                + "-coverage-prefix-map /private/tmp/checkout=/TUIST_SOURCE_ROOT",
            "OTHER_CFLAGS=$(inherited) $(TUIST_BINARY_CACHE_COVERAGE_CFLAGS_$(TUIST_BINARY_CACHE_COVERAGE))",
            "TUIST_BINARY_CACHE_COVERAGE_CFLAGS_YES=-fprofile-update=atomic "
                + "-fcoverage-prefix-map=/tmp/checkout=/TUIST_SOURCE_ROOT "
                + "-fcoverage-prefix-map=/private/tmp/checkout=/TUIST_SOURCE_ROOT",
        ])
    }
}
