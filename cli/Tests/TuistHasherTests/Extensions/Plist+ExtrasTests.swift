import TuistCore
import XcodeGraph
import Testing
@testable import TuistHasher

struct PlistrExtrasTests {
    @Test
    func test_normalize() throws {
        #expect(Plist.Value.string("test").normalize() as? String == "test")
        #expect(Plist.Value.integer(1).normalize() as? Int == 1)
        #expect(Plist.Value.real(1).normalize() as? Double == 1)
        #expect(Plist.Value.boolean(true).normalize() as? Bool == true)
        #expect(Plist.Value.array([.string("test")]).normalize() as? [String] == ["test"])
        #expect(Plist.Value.dictionary(["test": .string("tuist")]).normalize() as? [String: String] == ["test": "tuist"])
    }
}
