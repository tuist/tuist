import Foundation
import Framework2
import Framework3
import Framework4

public class Framework1File {
    private let framework2File = Framework2File()
    private let framework3File = Framework3File()
    private let framework4File = Framework4File()

    public init() {}

    public func hello() -> String {
        "Framework1File.hello()"
    }

    public func helloFromFramework2() -> String {
        "Framework1File -> \(framework2File.hello())"
    }

    public func helloFromFramework3() -> String {
        "Framework1File -> \(framework3File.hello())"
    }

    public func helloFromFramework4() -> String {
        "Framework1File -> \(framework4File.hello())"
    }
}
