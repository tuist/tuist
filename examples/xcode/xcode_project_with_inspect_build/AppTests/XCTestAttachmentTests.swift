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

    func testImageAttachment() {
        // Create a simple 10x10 red image using CoreGraphics
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let attachment = XCTAttachment(image: image)
        attachment.name = "xctest-image-attachment"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(true)
    }
}
