import Combine
import Foundation
import Security

@MainActor
final class AtlasEnvironmentPreviewData: ObservableObject {
    private let owner = "00000000-0000-4000-8000-000000000001"
    private let environment = "00000000-0000-4000-8000-000000000002"
    private let project = "00000000-0000-4000-8000-000000000003"
    private var selected = false
    private var stopping = false

    #if os(macOS)
    lazy var workstation: AtlasWorkstation = {
        let keychain = AtlasPreviewEnvironmentStorage()
        var configuration = AtlasWorkstationConfiguration()
        configuration.name = "Demo Mac"
        let data = try! JSONEncoder().encode(configuration)
        keychain.value = data
        return AtlasWorkstation(origin: URL(string: "https://atlas.example.org")!, request: request,
                                live: { _ in throw CancellationError() }, keychain: keychain)
    }()
    #endif

    func request(_ action: [String: Any]) async throws -> Data {
        let value: [String: Any]
        switch action["action"] as? String {
        case "list":
            value = ["owner_id": owner, "environments": [[
                "id": environment, "name": "Demo Mac", "enabled": true, "online": true,
                "terminal": true, "display": false, "projects": [["id": project, "name": "Example project"]]
            ]]]
        case "selection", "select":
            if action["action"] as? String == "select" { selected = action["environment_id"] as? String == environment }
            value = ["thread": ["id": action["thread_id"] as? String ?? "", "environment_id": selected ? environment as Any : NSNull(),
                                "environment_name": selected ? "Demo Mac" as Any : NSNull(),
                                "project_id": selected ? project as Any : NSNull()]]
        case "thread_commands":
            value = ["commands": ProcessInfo.processInfo.arguments.contains("--environment-jobs") ? [job()] : []]
        case "cancel_command":
            stopping = true
            value = ["received": true]
        default: throw CancellationError()
        }
        return try JSONSerialization.data(withJSONObject: value)
    }

    private func job() -> [String: Any] {
        let args = ProcessInfo.processInfo.arguments
        let status = args.contains("--environment-unknown") ? "unknown"
            : args.contains("--environment-completed") ? "settled"
            : args.contains("--environment-running") ? "claimed" : "queued"
        return [
            "id": "00000000-0000-4000-8000-000000000004", "message_id": "00000000-0000-4000-8000-000000000005",
            "environment_id": environment, "environment_name": "Demo Mac", "project_id": project,
            "project_name": "Example project", "digest": String(repeating: "a", count: 64),
            "command": "xcodebuild -project Example.xcodeproj -scheme Example -destination 'generic/platform=macOS' build",
            "status": status, "output": status == "claimed" ? "CompileSwift ExampleApp.swift\nLink Example.app"
                : status == "settled" ? "** BUILD SUCCEEDED **" : "",
            "success": status == "settled" ? true as Any : NSNull(), "cancel_requested": stopping,
            "progress_sequence": status == "claimed" ? 4 : 0, "execution_timeout_seconds": 1800
        ]
    }
}

#if os(macOS)
private final class AtlasPreviewEnvironmentStorage: AtlasKeychainAccess {
    var value: Data?
    func read(_ query: [CFString: Any]) -> (OSStatus, Data?) { (value == nil ? errSecItemNotFound : errSecSuccess, value) }
    func update(_ query: [CFString: Any], data: Data) -> OSStatus { value = data; return errSecSuccess }
    func insert(_ query: [CFString: Any]) -> OSStatus { value = query[kSecValueData] as? Data; return errSecSuccess }
    func delete(_ query: [CFString: Any]) -> OSStatus { value = nil; return errSecSuccess }
}
#endif
