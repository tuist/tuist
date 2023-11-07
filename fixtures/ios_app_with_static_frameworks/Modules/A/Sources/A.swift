import B
import C
import PrebuiltStaticFramework

public enum A {
    public static let value: String = "aValue"

    public static func printFromA() {
        print("print from A")
        B.printFromB()
        C.printFromC()
        print(StaticFrameworkClass().hello())
        print("---")
    }
}
