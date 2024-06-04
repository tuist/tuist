import Foundation
import ProjectDescription
import XcodeProjectGenerator

extension XcodeProjectGenerator.ScreenCaptureFormat {
    static func from(manifest: ProjectDescription.ScreenCaptureFormat) -> XcodeProjectGenerator.ScreenCaptureFormat {
        switch manifest {
        case .screenshots:
            return .screenshots
        case .screenRecording:
            return .screenRecording
        }
    }
}
