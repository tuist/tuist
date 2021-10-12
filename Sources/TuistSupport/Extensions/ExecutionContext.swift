/// Execution Context
///
/// Defines a context for operations to be performed in.
/// e.g. `.concurrent` or `.serial`
///
public struct ExecutionContext {
    public enum ExecutionType {
        case serial
        case concurrent
    }

    public var executionType: ExecutionType
    public init(executionType: ExecutionType) {
        self.executionType = executionType
    }

    public static var serial: ExecutionContext {
        ExecutionContext(executionType: .serial)
    }

    public static var concurrent: ExecutionContext {
        ExecutionContext(executionType: .concurrent)
    }
}
