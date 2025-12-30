import Mocker
import ModuleATestSupporting
import XCTest

class FrameworkATests: XCTestCase {
    var sut: URLSession!

    override func setUp() {
        super.setUp()

        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockingURLProtocol.self]

        sut = URLSession(configuration: configuration)

        NetworkResponseMocks.testMock.register()
    }

    func testMock() async throws {
        let (_, response) = try await sut.data(from: URL(string: "https://apple.com")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
