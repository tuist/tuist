import Foundation
import ModuleA

public class ModuleBFile {
    public init() {}

    public func hello() -> String {
        let classA = ClassA()
        return "ModuleBFile.hello() -> \(classA.hello())"
    }
}
