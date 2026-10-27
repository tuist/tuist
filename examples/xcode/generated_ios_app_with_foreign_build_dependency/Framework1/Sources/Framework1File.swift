import Foundation
import SharedKMP

public class Framework1File {
    public init() {}
    public func greeting() -> String {
        let greeting = Greeting()
        return greeting.greet()
    }
}
