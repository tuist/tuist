internal import ResourcesLib

public enum Greeter {
    public static func greeting() -> String {
        ResourcesProvider.greeting()
    }
}
