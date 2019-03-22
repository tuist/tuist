/// Implements a Stack - helper class for push/pop that uses an array internally.
public struct Stack<T> {
    private var array = [T]()

    public init() {}

    public var isEmpty: Bool {
        return array.isEmpty
    }

    public var count: Int {
        return array.count
    }

    public mutating func push(_ element: T) {
        array.append(element)
    }

    public mutating func pop() -> T? {
        return array.popLast()
    }
}
