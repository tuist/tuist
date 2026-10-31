import Testing
@testable import TuistSupport

struct MacOSPrivateSymlinkTwinTests {
    @Test(arguments: [
        ("/private/tmp/checkout", "/tmp/checkout"),
        ("/tmp/checkout", "/private/tmp/checkout"),
        ("/private/var/folders/x", "/var/folders/x"),
        ("/var", "/private/var"),
        ("/private/etc", "/etc"),
    ])
    func twin_ofAPathUnderASymlinkedDirectory(path: String, twin: String) {
        #expect(macOSPrivateSymlinkTwin(of: path) == twin)
    }

    @Test(arguments: ["/private/opt/x", "/private", "/tmpfiles/x", "/Users/ci/checkout", "/"])
    func twin_ofAnyOtherPathIsNil(path: String) {
        #expect(macOSPrivateSymlinkTwin(of: path) == nil)
    }
}
