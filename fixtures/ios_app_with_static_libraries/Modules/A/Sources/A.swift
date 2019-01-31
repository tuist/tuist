import B

public class A {

    public static let value: String = "aValue"

    static public func printFromA() {
        print("print from A")
        B.printFromB()
    }

}
