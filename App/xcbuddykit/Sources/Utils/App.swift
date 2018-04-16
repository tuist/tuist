import Foundation

/// Util class that contains information about the app.
public class App {
    /// App's bundle information dictionary.
    private let infoDictionary: [String: Any]

    /// Default constructor.
    public convenience init() {
        self.init(infoDictionary: Bundle.app.infoDictionary!)
    }

    /// Initializes the app with the app's bundle info dictionary.
    ///
    /// - Parameter infoDictionary: info dictionary.
    public init(infoDictionary: [String: Any]) {
        self.infoDictionary = infoDictionary
    }

    /// App version.
    public var version: String {
        return infoDictionary["CFBundleShortVersionString"]! as! String
    }
}
