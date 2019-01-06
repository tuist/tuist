import Foundation

@testable import TuistKit

final class MockXcodeBuildOutputParser: XcodeBuildOutputParsing {
    var parseStub: ((String) -> XcodeBuildOutputEvent?)?

    func parse(line: String) -> XcodeBuildOutputEvent? {
        return parseStub?(line) ?? nil
    }
}
