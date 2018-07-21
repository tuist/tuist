import Basic
import Foundation
import Utility
import XCTest
@testable import xpmkit

final class InitTests: XCTestCase {
    var subject: InitCommand!
    var parser: ArgumentParser!

    override func setUp() {
        parser = ArgumentParser(usage: "test", overview: "test")
        subject = InitCommand(parser: parser)
    }

    func test_init_when_ios_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "ios"])
        try subject.run(with: result)
    }
}
