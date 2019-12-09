import Foundation
@testable import SPMUtility

public extension ArgumentParser.Result {
    static func test(parser: ArgumentParser = ArgumentParser(usage: "test", overview: "overview")) -> ArgumentParser.Result {
        ArgumentParser.Result(parser: parser, parent: nil)
    }
}
