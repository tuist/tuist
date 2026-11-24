import NestedKit
import QuotedKit

public func featureValue() -> Int {
    NKValue.value() + QKValue.value() - 1
}
