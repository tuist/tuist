import AnyCodable
import Foundation
import Path
import TuistCore

/// Commands that conform to `HasTrackableParameters` can report extra parameters that are only known at runtime
public protocol HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate? { get set }
    /// ID that uniquely identifies the command run
    var runId: String { get set }
}

/// `TrackableParametersDelegate` contains the callback that should be called
/// before running a command, with extra parameters that are only known at runtime
public protocol TrackableParametersDelegate: AnyObject {
    var targetHashes: [CommandEventGraphTarget: String]? { get set }
    var graphPath: AbsolutePath? { get set }
    func addParameters(_ parameters: [String: AnyCodable])
}
