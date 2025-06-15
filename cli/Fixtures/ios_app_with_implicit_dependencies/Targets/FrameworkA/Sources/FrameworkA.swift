import Foundation
import FrameworkB

public enum FrameworkA {
    public static func frameworkA() {
        FrameworkB.frameworkB()
        print("frameworkB")
    }
}
