#if !os(Linux)
    import Foundation
    import Mockable
    import OpenAPIRuntime
    import TuistLogging

    @Mockable
    public protocol UploadAppLogsServicing: Sendable {
        func uploadAppLogs(_ entries: [ApplicationLogEntry], serverURL: URL) async throws
    }

    public enum UploadAppLogsServiceError: LocalizedError, Equatable {
        /// The server refused the batch itself, so sending it again cannot succeed.
        case rejected(Int)
        /// The server could not take the batch right now, so it should be sent again later.
        case unavailable(Int)

        public var errorDescription: String? {
            switch self {
            case let .rejected(statusCode):
                return "The Tuist server rejected the app logs with status code \(statusCode)."
            case let .unavailable(statusCode):
                return "The Tuist server could not accept the app logs, status code \(statusCode)."
            }
        }
    }

    public struct UploadAppLogsService: UploadAppLogsServicing {
        public init() {}

        public func uploadAppLogs(_ entries: [ApplicationLogEntry], serverURL: URL) async throws {
            let client = Client.authenticated(serverURL: serverURL)

            let response = try await client.uploadAppLogs(
                .init(
                    body: .json(
                        .init(
                            app: .init(
                                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                                os_version: ProcessInfo.processInfo.operatingSystemVersionString,
                                platform: Self.platform,
                                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                                    ?? "unknown"
                            ),
                            entries: entries.map {
                                .init(
                                    launch_id: $0.launchID,
                                    level: .init(rawValue: $0.level.rawValue) ?? .info,
                                    message: $0.message,
                                    source: $0.source,
                                    timestamp: $0.timestamp
                                )
                            }
                        )
                    )
                )
            )

            switch response {
            case .accepted:
                return
            case .badRequest:
                throw UploadAppLogsServiceError.rejected(400)
            case .forbidden:
                throw UploadAppLogsServiceError.rejected(403)
            case .unauthorized:
                throw UploadAppLogsServiceError.unavailable(401)
            case .tooManyRequests:
                throw UploadAppLogsServiceError.unavailable(429)
            case .serviceUnavailable:
                throw UploadAppLogsServiceError.unavailable(503)
            case let .undocumented(statusCode, _):
                throw UploadAppLogsServiceError.unavailable(statusCode)
            }
        }

        private static var platform: Operations.uploadAppLogs.Input.Body.jsonPayload.appPayload.platformPayload {
            #if os(macOS)
                .macos
            #else
                .ios
            #endif
        }
    }
#endif
