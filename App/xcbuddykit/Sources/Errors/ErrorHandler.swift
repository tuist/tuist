import Foundation
import Bugsnag

public protocol ErrorHandling: AnyObject {
    
}

fileprivate var started: Bool = false

public class ErrorHandler: ErrorHandling {
    
    public init() {
        Bugsnag.notifyError(NSError.init(domain: "domain", code: 0, userInfo: nil))
        if !started {
            if let apiKey = Bundle.main.object(forInfoDictionaryKey: "BUGSNAG_API_KEY") as? String {
                Bugsnag.start(withApiKey: apiKey)
            }
            started = true
        }
    }
    
    func notify(error: Error) {
        if !started { return }
        Bugsnag.notifyError(error)
    }
    
}
