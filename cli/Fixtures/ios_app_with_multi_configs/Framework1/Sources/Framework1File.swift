import Foundation
import Framework2

public class Framework1File {
    private let framework2File = Framework2File()

    public init() {}

    public func hello() -> String {
        "Framework1File.hello()"
    }

    public func helloFromFramework2() -> String {
        "Framework1File -> \(framework2File.hello())"
    }
}
