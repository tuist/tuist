/// Implements a Stack - helper class for push/pop that uses an array internally.
public struct Stack<T> {
    private var array = [T]()

    public init() {}

    public var isEmpty: Bool {
        array.isEmpty
    }

    public var count: Int {
        array.count
    }

    public mutating func push(_ element: T) {
        array.append(element)
    }

    public mutating func pop() -> T? {
        array.popLast()
    }
}
