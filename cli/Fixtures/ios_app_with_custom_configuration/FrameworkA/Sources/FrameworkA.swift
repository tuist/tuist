import Foundation

public enum FrameworkA {
    public static func hello() {
        print("Hello, from your FrameworkA")
    }

    #if DEBUG_MACRO
        public static func helloDebugMacro() {
            print("Hello, from your FrameworkA (DEBUG_MACRO only)")
        }
    #endif
}
