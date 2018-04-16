import Foundation
import Sparkle

fileprivate var _app: SPUStandardUpdaterController!

// MARK: - SPUStandardUpdaterController (App)

extension SPUStandardUpdaterController {
    /// Returns an updates controller to be used from the app.
    static var app: SPUStandardUpdaterController {
        if _app != nil { return _app }
        _app = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)
        return _app
    }
}
