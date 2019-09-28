import Foundation
import LibraryA

public class StaticFrameworkClass {
    public init() {}

    public func hello() -> String {
        return "StaticFrameworkClass.hello()"
    }
    
    public func packageCode() -> String {
        return LibraryAClass().text
    }
}
