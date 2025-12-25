import CasePaths

@CasePathable
enum AppAction {
    case home
}

public enum ModuleA {
    public static func test() {
        print("Module A")
    }
}
