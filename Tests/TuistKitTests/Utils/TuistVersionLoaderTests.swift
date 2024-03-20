import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class TuistVersionLoaderTests: TuistUnitTestCase {
    private var mockSystem: MockSystem!

    private var sut: TuistVersionLoader!

    override func setUp() {
        super.setUp()
        mockSystem = MockSystem()
        sut = TuistVersionLoader(system: mockSystem)
    }

    func test_getVersion_passesRightArguments() throws {
        // given
        let version = "4.0.1"
        mockSystem.stubs = ["tuist version": (stderror: nil, stdout: version, exitstatus: 0)]

        // when
        let result = try sut.getVersion()

        // then
        XCTAssertTrue(mockSystem.called(["tuist", "version"]))
        XCTAssertEqual(result, "4.0.1")
    }

    override func tearDown() {
        mockSystem = nil
        sut = nil
        super.tearDown()
    }
}
