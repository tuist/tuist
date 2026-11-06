import DynamicModule

public enum Feature {
    public static var answer: Int { DynamicState.shared.value }
}
