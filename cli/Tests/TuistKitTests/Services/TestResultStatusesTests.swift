import Testing
import XCResultParser

@Suite
struct TestResultStatusesTests {
    @Test
    func hasFailures_returnsTrue_whenAnyTestFailed() {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: nil, module: "AppTests", status: .passed),
            .init(name: "testB()", testSuite: nil, module: "AppTests", status: .failed),
        ])
        #expect(statuses.hasFailures == true)
    }

    @Test
    func hasFailures_returnsFalse_whenAllTestsPassed() {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: nil, module: "AppTests", status: .passed),
            .init(name: "testB()", testSuite: nil, module: "AppTests", status: .passed),
        ])
        #expect(statuses.hasFailures == false)
    }

    @Test
    func passingModuleNames_returnsOnlyFullyPassingModules() {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: nil, module: "AppTests", status: .passed),
            .init(name: "testB()", testSuite: nil, module: "AppTests", status: .failed),
            .init(name: "testC()", testSuite: nil, module: "CoreTests", status: .passed),
            .init(name: "testD()", testSuite: nil, module: "CoreTests", status: .passed),
        ])
        #expect(statuses.passingModuleNames() == ["CoreTests"])
    }

    @Test
    func passingModuleNames_returnsAll_whenNothingFailed() {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: nil, module: "AppTests", status: .passed),
            .init(name: "testB()", testSuite: nil, module: "CoreTests", status: .passed),
        ])
        #expect(statuses.passingModuleNames() == ["AppTests", "CoreTests"])
    }

    @Test
    func testCasesByModule_groupsCorrectly() {
        let statuses = TestResultStatuses(testCases: [
            .init(name: "testA()", testSuite: nil, module: "AppTests", status: .passed),
            .init(name: "testB()", testSuite: nil, module: "CoreTests", status: .passed),
            .init(name: "testC()", testSuite: nil, module: "AppTests", status: .failed),
        ])
        let byModule = statuses.testCasesByModule
        #expect(byModule["AppTests"]?.count == 2)
        #expect(byModule["CoreTests"]?.count == 1)
    }
}
