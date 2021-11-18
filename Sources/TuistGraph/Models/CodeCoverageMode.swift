import Foundation

public enum CodeCoverageMode: Hashable {
    case all, relevant
    case targets([TargetReference])
}
