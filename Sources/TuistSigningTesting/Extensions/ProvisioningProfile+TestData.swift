import TSCBasic
import XCTest
@testable import TuistSigning

public extension ProvisioningProfile {
    static func test(
        path: AbsolutePath = AbsolutePath("/targetName.configurationName.mobileprovision"),
        name: String = "name",
        targetName: String = "targetName",
        configurationName: String = "configurationName",
        uuid: String = "uuid",
        teamId: String = "teamId",
        appId: String = "appId",
        appIdName: String = "appIdName",
        applicationIdPrefix: [String] = [],
        platforms: [String] = ["iOS"],
        expirationDate: Date = Date().addingTimeInterval(100)
    ) -> ProvisioningProfile {
        ProvisioningProfile(
            path: path,
            name: name,
            targetName: targetName,
            configurationName: configurationName,
            uuid: uuid,
            teamId: teamId,
            appId: appId,
            appIdName: appIdName,
            applicationIdPrefix: applicationIdPrefix,
            platforms: platforms,
            expirationDate: expirationDate
        )
    }
}
