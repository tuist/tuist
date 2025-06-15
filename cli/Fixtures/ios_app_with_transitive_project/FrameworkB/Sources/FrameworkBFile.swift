import Foundation
import FrameworkC

public class FrameworkBFile {
    private let frameworkCFile = FrameworkCFile()

    public init() {}

    public func hello() -> String {
        "FrameworkBFile.hello()"
    }

    public func helloFromFrameworkC() -> String {
        "FrameworkBFile -> \(frameworkCFile.hello())"
    }
}
