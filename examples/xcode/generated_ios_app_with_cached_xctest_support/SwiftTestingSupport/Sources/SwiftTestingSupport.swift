import Testing

public enum SwiftTestingSupport {
    public static let expectedMessage = "cached-xctest-support"

    public static func expectMessage(_ message: String) {
        #expect(message == expectedMessage)
    }
}
