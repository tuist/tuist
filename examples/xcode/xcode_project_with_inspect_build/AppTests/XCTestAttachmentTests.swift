import XCTest
@testable import App

final class XCTestAttachmentTests: XCTestCase {
    func testTextAttachment() {
        let text = "Hello from XCTest - text attachment"
        let attachment = XCTAttachment(string: text)
        attachment.name = "xctest-text-attachment"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(true)
    }

    func testDataAttachment() {
        let data = Data("Binary data from XCTest".utf8)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
        attachment.name = "xctest-data-attachment.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(true)
    }

    func testImageAttachment() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "screenshot2", withExtension: "png")!
        let data = try Data(contentsOf: url)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "xctest-image-attachment.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(true)
    }

    func testFailingWithImageAttachment() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "screenshot2", withExtension: "png")!
        let data = try Data(contentsOf: url)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "failure-screenshot.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("This test intentionally fails with an image attachment")
    }
}
