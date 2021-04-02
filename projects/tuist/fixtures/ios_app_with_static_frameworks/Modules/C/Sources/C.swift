import Foundation
import D
public class C {
    public static let value: String = "cValue"

    public static func printFromC() {
        print("print from C")
        D.printFromD()
    }
}
