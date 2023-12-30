import Alamofire
import ComposableArchitecture

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")

        // Use ComposableArchitecture to make sure it links fine
        _ = EmptyReducer<Never, Never>()
    }
}
