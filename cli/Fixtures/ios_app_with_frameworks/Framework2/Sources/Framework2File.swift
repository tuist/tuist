import Foundation
import Framework3

public class Framework2File {
    public init() {}

    public func hello() -> String {
        Framework3File().hello()
        return "Framework2File.hello()"
    }
}
