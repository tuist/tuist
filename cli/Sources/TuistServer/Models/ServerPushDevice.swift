import Foundation

public struct ServerPushDevice: Equatable, Hashable, Identifiable, Sendable {
    public let registrationID: String
    public let installationID: String
    public let platform: String
    public let name: String?
    public let registeredAt: Date
    public let lastSeenAt: Date

    public var id: String { registrationID }

    public init(
        registrationID: String,
        installationID: String,
        platform: String,
        name: String?,
        registeredAt: Date,
        lastSeenAt: Date
    ) {
        self.registrationID = registrationID
        self.installationID = installationID
        self.platform = platform
        self.name = name
        self.registeredAt = registeredAt
        self.lastSeenAt = lastSeenAt
    }

    init(_ device: Operations.listPushDevices.Output.Ok.Body.jsonPayload.devicesPayloadPayload) {
        registrationID = device.registration_id
        installationID = device.installation_id
        platform = device.platform
        name = device.name
        registeredAt = device.registered_at
        lastSeenAt = device.last_seen_at
    }

    #if DEBUG
        public static func test(
            registrationID: String = "registration-id",
            installationID: String = "installation-id",
            platform: String = "ios",
            name: String? = "iPhone 17 Pro",
            registeredAt: Date = Date(timeIntervalSince1970: 0),
            lastSeenAt: Date = Date(timeIntervalSince1970: 0)
        ) -> Self {
            .init(
                registrationID: registrationID,
                installationID: installationID,
                platform: platform,
                name: name,
                registeredAt: registeredAt,
                lastSeenAt: lastSeenAt
            )
        }
    #endif
}
