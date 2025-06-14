import Foundation

extension Sequence {
    public func reduceWithIndex<Result>(
        into initialResult: Result,
        _ updateAccumulatingResult: (inout Result, Self.Element, Int) throws -> Void
    ) rethrows -> Result {
        var count = 0
        return try reduce(into: initialResult) { result, element in
            try updateAccumulatingResult(&result, element, count)
            count += 1
        }
    }
}
