import Foundation

private class AppBundle {}

public extension Bundle {
    static var app: Bundle {
        return Bundle(for: AppBundle.self)
    }
}