import Basic
import Foundation

public enum GraphDependencyReference: Equatable, Comparable, Hashable {
    case absolute(AbsolutePath)
    case product(target: String, productName: String)
    case sdk(AbsolutePath, SDKStatus)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .absolute(path):
            hasher.combine(path)
        case let .product(target, productName):
            hasher.combine(target)
            hasher.combine(productName)
        case let .sdk(path, status):
            hasher.combine(path)
            hasher.combine(status)
        }
    }

    public static func == (lhs: GraphDependencyReference, rhs: GraphDependencyReference) -> Bool {
        switch (lhs, rhs) {
        case let (.absolute(lhsPath), .absolute(rhsPath)):
            return lhsPath == rhsPath
        case let (.product(lhsTarget, lhsProductName), .product(rhsTarget, rhsProductName)):
            return lhsTarget == rhsTarget && lhsProductName == rhsProductName
        case let (.sdk(lhsPath, lhsStatus), .sdk(rhsPath, rhsStatus)):
            return lhsPath == rhsPath && lhsStatus == rhsStatus
        default:
            return false
        }
    }

    public static func < (lhs: GraphDependencyReference, rhs: GraphDependencyReference) -> Bool {
        switch (lhs, rhs) {
        case let (.absolute(lhsPath), .absolute(rhsPath)):
            return lhsPath < rhsPath
        case let (.product(lhsTarget, lhsProductName), .product(rhsTarget, rhsProductName)):
            if lhsTarget == rhsTarget {
                return lhsProductName < rhsProductName
            }
            return lhsTarget < rhsTarget
        case let (.sdk(lhsPath, _), .sdk(rhsPath, _)):
            return lhsPath < rhsPath
        case (.sdk, .absolute):
            return true
        case (.sdk, .product):
            return true
        case (.product, .absolute):
            return true
        default:
            return false
        }
    }
}
