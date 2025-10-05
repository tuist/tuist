import AIProxy
import Alamofire
import FirebaseCrashlytics

public enum AppKit {
    public static func start() {
        // Use Alamofire to make sure it links fine
        _ = AF.download("http://www.tuist.io")
        AIProxy.configure(
            logLevel: .debug,
            printRequestBodies: false, // Flip to true for library development
            printResponseBodies: false, // Flip to true for library development
            resolveDNSOverTLS: true,
            useStableID: false, // Please see the docstring if you'd like to enable this
        )
    }
}
