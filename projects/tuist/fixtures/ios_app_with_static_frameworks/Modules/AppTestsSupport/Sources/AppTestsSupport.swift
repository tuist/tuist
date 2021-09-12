import Foundation
import PrebuiltStaticFramework

public class AppTestsSupport {
    public static let value: String = "appTestsSupportValue"

    public static func printFromAppTestsSupport() {
        print("print from AppTestsSupport")
        print(StaticFrameworkClass().hello())
    }
}
