import Foundation
import Testing
@testable import XCResultParser

struct TestEnumerationTests {
    @Test func readsXcodebuildsFlatListAcrossTestPlans() throws {
        let output = """
        {
          "errors": [],
          "values": [
            {
              "testPlan": "App",
              "enabledTests": [
                {"identifier": "AppTests/MathTests/testAdd()"},
                {"identifier": "AppTests/Outer/Nested/never()"},
                {"identifier": "AppTests/parameterized(value:)"}
              ],
              "disabledTests": [{"identifier": "AppTests/MathTests/testDisabled()"}]
            },
            {
              "testPlan": "Smoke",
              "enabledTests": [{"identifier": "AppTests/MathTests/testDisabled()"}],
              "disabledTests": [{"identifier": "AppTests/MathTests/testAdd()"}, {"identifier": "AppTests"}]
            }
          ]
        }
        """

        let enumeration = try TestEnumeration(xcodebuildOutput: Data(output.utf8))

        #expect(enumeration.tests == [
            .init(module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true),
            .init(module: "AppTests", suite: "Nested", name: "never()", enabled: true),
            .init(module: "AppTests", suite: "", name: "parameterized(value:)", enabled: true),
            .init(module: "AppTests", suite: "MathTests", name: "testDisabled()", enabled: true),
        ])
    }

    @Test func keepsTheSlashesOfAParameterListInTheName() {
        #expect(
            TestEnumeration.Test(identifier: "AppTests/PathTests/resolves(a/b:)", enabled: false)
                == .init(module: "AppTests", suite: "PathTests", name: "resolves(a/b:)", enabled: false)
        )
        #expect(TestEnumeration.Test(identifier: "AppTests", enabled: true) == nil)
    }

    @Test func travelsInTheResultBundleAndReachesTheSummary() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let enumeration = TestEnumeration(tests: [.init(module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true)])

        #expect(TestEnumeration.read(fromResultBundle: bundle) == nil)
        try enumeration.write(toResultBundle: bundle)
        #expect(TestEnumeration.read(fromResultBundle: bundle) == enumeration)

        let summary = TestSummary(testPlanName: nil, status: .passed, duration: nil, testModules: [])
        #expect(summary.applying(enumeration: nil).enumeratedTests == nil)
        #expect(summary.applying(enumeration: enumeration).enumeratedTests == enumeration.tests)
    }
}
