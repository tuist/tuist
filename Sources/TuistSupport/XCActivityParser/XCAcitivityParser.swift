import Foundation
import Mockable
import Path
import XCLogParser

@Mockable
public protocol XCActivityParsing {
    func parse(_ path: AbsolutePath) throws -> XCActivityLog
}

public struct XCActivityParser: XCActivityParsing {
    public init() {}

    public func parse(_ path: AbsolutePath) throws -> XCActivityLog {
        let activityLog = try XCLogParser.ActivityParser().parseActivityLogInURL(
            path.url,
            redacted: false,
            withoutBuildSpecificInformation: false
        )

        return XCActivityLog(
            version: activityLog.version,
            mainSection: XCActivityLogSection(
                uniqueIdentifier: activityLog.mainSection.uniqueIdentifier,
                timeStartedRecording: activityLog.mainSection.timeStartedRecording,
                timeStoppedRecording: activityLog.mainSection.timeStoppedRecording
            )
        )
    }
}
