import Foundation
import Path

public struct CrashReport {
    public let exceptionType: String?
    public let signal: String?
    public let exceptionSubtype: String?
    public let filePath: AbsolutePath
    public let triggeredThreadFrames: String?

    public init(
        exceptionType: String?,
        signal: String?,
        exceptionSubtype: String?,
        filePath: AbsolutePath,
        triggeredThreadFrames: String? = nil
    ) {
        self.exceptionType = exceptionType
        self.signal = signal
        self.exceptionSubtype = exceptionSubtype
        self.filePath = filePath
        self.triggeredThreadFrames = triggeredThreadFrames
    }
}
