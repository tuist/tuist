import Foundation

private class StaticFramework2ResourcesBundle {}

public extension Bundle {
    static var staticFramework2Resources: Bundle {
        return Bundle(for: StaticFramework2ResourcesBundle.self)
    }
}