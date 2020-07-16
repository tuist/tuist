import Foundation

public extension Bundle {
    static var staticFramework3: Bundle {
        return Bundle(url: Bundle.main.bundleURL.appendingPathComponent("StaticFramework3Resources.bundle"))!
    }
}