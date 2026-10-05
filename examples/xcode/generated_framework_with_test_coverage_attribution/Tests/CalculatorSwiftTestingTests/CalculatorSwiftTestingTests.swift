import Calculator
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution, .serialized)
struct CalculatorSwiftTestingTests {
    @Test func subtract() {
        #expect(Calculator.subtract(3, 2) == 1)
    }
}
