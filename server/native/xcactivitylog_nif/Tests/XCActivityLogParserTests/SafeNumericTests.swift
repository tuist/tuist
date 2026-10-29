import Testing

@testable import XCActivityLogParser

@Suite
struct SafeNumericTests {
    @Test func location_mapsMissingLocationSentinelToZero() {
        #expect(SafeNumeric.location(UInt64.max) == 0)
    }

    @Test func location_clampsValuesAboveIntMax() {
        #expect(SafeNumeric.location(UInt64(Int.max) + 1) == Int.max)
    }

    @Test func location_passesThroughRealLineNumbers() {
        #expect(SafeNumeric.location(0) == 0)
        #expect(SafeNumeric.location(1) == 1)
        #expect(SafeNumeric.location(48273) == 48273)
    }

    @Test func milliseconds_convertsFiniteSeconds() {
        #expect(SafeNumeric.milliseconds(1.5) == 1500)
        #expect(SafeNumeric.milliseconds(0) == 0)
        #expect(SafeNumeric.milliseconds(0.0001) == 1)
    }

    @Test func milliseconds_roundsTowardZeroWhenAsked() {
        #expect(SafeNumeric.milliseconds(1.9999, rounding: .towardZero) == 1999)
    }

    @Test func milliseconds_mapsNonFiniteToZero() {
        #expect(SafeNumeric.milliseconds(.nan) == 0)
        #expect(SafeNumeric.milliseconds(.infinity) == 0)
        #expect(SafeNumeric.milliseconds(-.infinity) == 0)
    }

    @Test func milliseconds_mapsSecondsThatOverflowToInfinityToZero() {
        #expect(SafeNumeric.milliseconds(.greatestFiniteMagnitude) == 0)
        #expect(SafeNumeric.milliseconds(-.greatestFiniteMagnitude) == 0)
    }

    @Test func milliseconds_clampsFiniteMagnitudesBeyondIntRange() {
        #expect(SafeNumeric.milliseconds(1e30) == Int.max)
        #expect(SafeNumeric.milliseconds(-1e30) == Int.min)
    }
}
