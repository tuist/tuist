import Foundation

/// Commands that conform to `HasTrackableParameters` can report extra parameters that are only known at runtime
protocol HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate? { get set }
}

/// `TrackableParametersDelegate` contains the callback that should be called
/// before running a command, with extra parameters that are only known at runtime
protocol TrackableParametersDelegate: AnyObject {
    func willRun(withParameters: [String: String])
}
