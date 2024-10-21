import Foundation
import ProjectDescription
import XcodeGraph

extension XcodeGraph.ScreenCaptureFormat {
    static func from(manifest: ProjectDescription.ScreenCaptureFormat) -> XcodeGraph.ScreenCaptureFormat {
        switch manifest {
        case .screenshots:
            return .screenshots
        case .screenRecording:
            return .screenRecording
        }
    }
}
