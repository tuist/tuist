import Alamofire
import FirebaseCrashlytics

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")
    }
}
