import Foundation
import FrameworkB

public class FrameworkAFile {
    private let frameworkBFile = FrameworkBFile()

    public init() {}

    public func hello() -> String {
        "FrameworkAFile.hello()"
    }

    public func helloFromFrameworkB() -> String {
        "Framework1File -> \(frameworkBFile.hello())"
    }
}
