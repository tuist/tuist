import Foundation
import FrameworkB

public class FrameworkAFile {
    private let frameworkBFile = FrameworkBFile()

    public init() {}

    public func hello() -> String {
        "FrameworkAFile.hello()"
    }

    public func helloFromFrameworkB() -> String {
        "FrameworkAFile -> \(frameworkBFile.hello())"
    }

    public func helloFromFrameworkC() -> String {
        "FrameworkAFile -> \(frameworkBFile.helloFromFrameworkC())"
    }
}
