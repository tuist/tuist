import Foundation
import FrameworkB

public struct FrameworkA {
    public static func frameworkA() {
        FrameworkB.frameworkB()
        print("frameworkB")
    }
}

