import Foundation
import Framework2

public class Framework1File {

    private let framework2File = Framework2File()

    public init() {}

    public func hello() -> String {
        return "Framework1File.hello()"
    }

    public func helloFromFramework2() -> String {
        return "Framework1File -> \(framework2File.hello())"
    }
}
