import Foundation

private class StaticFrameworkResourcesBundle {}

public extension Bundle {
    static var staticFrameworkResources: Bundle {
        return Bundle(for: StaticFrameworkResourcesBundle.self)
    }
}