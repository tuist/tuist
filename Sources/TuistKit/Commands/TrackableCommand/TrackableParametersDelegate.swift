import AnyCodable
import Foundation

/// Commands that conform to `HasTrackableParameters` can report extra parameters that are only known at runtime
public protocol HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate? { get set }
}

/// `TrackableParametersDelegate` contains the callback that should be called
/// before running a command, with extra parameters that are only known at runtime
public protocol TrackableParametersDelegate: AnyObject {
    func addParameters(_ parameters: [String: AnyCodable])
}
