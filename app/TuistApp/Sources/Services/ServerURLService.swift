import Foundation
import Mockable
import TuistSupport

@Mockable
protocol ServerURLServicing {
    func serverURL() -> URL
}

struct ServerURLService: ServerURLServicing {
    func serverURL() -> URL {
        Constants.URLs.production
    }
}
