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

    @Test func swiftTestingImageAttachment() {
        let pngData = createMinimalPNG()
        Attachment.record(pngData, named: "swift-testing-image.png")
        #expect(true)
    }

    @Test func swiftTestingStringAttachment() {
        Attachment.record("Hello from Swift Testing - string attachment", named: "swift-testing-string.txt")
        #expect(true)
    }

    private func createMinimalPNG() -> Data {
        var data = Data()
        data.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let ihdr: [UInt8] = [
            0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00, 0x00, 0x02,
            0x08, 0x02, 0x00, 0x00, 0x00,
            0x72, 0xD1, 0x09, 0x63,
        ]
        data.append(contentsOf: ihdr)
        let idat: [UInt8] = [
            0x00, 0x00, 0x00, 0x1C,
            0x49, 0x44, 0x41, 0x54,
            0x78, 0x01, 0x62, 0x64, 0xF8, 0xCF, 0xC0, 0x00,
            0x04, 0x0C, 0x0C, 0xFF, 0x19, 0x18, 0x00, 0x00,
            0x00, 0xFF, 0xFF, 0x03, 0x00, 0x01, 0x29, 0x00,
            0x19,
            0xA7, 0x6F, 0x43, 0xAF,
        ]
        data.append(contentsOf: idat)
        let iend: [UInt8] = [
            0x00, 0x00, 0x00, 0x00,
            0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82,
        ]
        data.append(contentsOf: iend)
        return data
    }
}

@Test func topLevelTest() async throws {
    #expect(true == true)
}
