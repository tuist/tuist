import Foundation
import LibraryA

public class StaticFrameworkClass {
    public init() {}

    public func hello() -> String {
        "StaticFrameworkClass.hello()"
    }

    public func packageCode() -> String {
        LibraryAClass().text
    }
}
