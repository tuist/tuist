import Foundation

#if canImport(Framework2)
import Framework2
#endif

public class Framework1File {
    
    #if canImport(Framework2)
    private let framework2File = Framework2File()
    #endif
    
    public init() {}

    public func hello() -> String {
        return "Framework1File.hello()"
    }

    #if canImport(Framework2)
    public func helloFromFramework2() -> String {
        return "Framework1File -> \(framework2File.hello())"
    }
    #endif
}
