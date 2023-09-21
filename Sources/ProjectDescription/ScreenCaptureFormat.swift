import Foundation

/// Preferred screen capture format for UI tests results in Xcode 15+
///
/// Available options are screen recordings and screenshots.
///
/// In Xcode 15 screen recordings are enabled by default (in favour of screenshots).
/// This setting is ignored by Xcode 14.x and prior.
///
public enum ScreenCaptureFormat: String, Codable {
    /// Screenshots
    case screenshots
    /// Automatic screen recordings
    case screenRecording
}
