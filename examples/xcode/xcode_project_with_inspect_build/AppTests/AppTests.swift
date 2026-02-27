import Foundation
import Testing
@testable import App

struct AppTests {
    @Test func example() async throws {
        #expect(true == true)
    }

    @Test func swiftTestingTextAttachment() {
        let data = Data("Hello from Swift Testing - text attachment".utf8)
        Attachment.record(data, named: "swift-testing-text.txt")
        #expect(true)
    }

    @Test func swiftTestingImageAttachment() throws {
        let url = Bundle(for: XCTestAttachmentTests.self).url(forResource: "screenshot1", withExtension: "png")!
        let data = try Data(contentsOf: url)
        Attachment.record(data, named: "swift-testing-image.png")
        #expect(true)
    }

    @Test func swiftTestingStringAttachment() {
        Attachment.record("Hello from Swift Testing - string attachment", named: "swift-testing-string.txt")
        #expect(true)
    }
}

@Test func topLevelTest() async throws {
    #expect(true == true)
}
