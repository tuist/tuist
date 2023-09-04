import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.ScreenCaptureFormat {
    static func from(manifest: ProjectDescription.ScreenCaptureFormat) -> TuistGraph.ScreenCaptureFormat {
        switch manifest {
        case .screenshots:
            return .screenshots
        case .screenRecording:
            return .screenRecording
        }
    }
}
