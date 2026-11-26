#if os(iOS) && targetEnvironment(simulator)
    import Foundation
    import LuftCore
    import NativeShell
    import SwiftUI

    /// Opting in with even an incomplete connection stays here: never fall back to
    /// sign-in, a saved session, or live data. This entire root is absent on devices.
    struct WorkspacePreview: View {
        static var requested: Bool {
            let environment = ProcessInfo.processInfo.environment
            return environment["LUFT_WORKSPACE_URL"] != nil || environment["LUFT_WORKSPACE_TOKEN"] != nil
        }

        @State private var client = WorkspacePreviewClient()
        @State private var preferredColumn = NavigationSplitViewColumn.detail
        @State private var contextualSession = false

        var body: some View {
            NavigationSplitView(preferredCompactColumn: $preferredColumn) {
                List {
                    Text("Local workspace preview").font(.headline)
                    Text(verbatim: client.title).font(.subheadline)
                    if client.modules.contains(where: { $0.id == "support.inbox" }) {
                        Section("Sessions") {
                            Button("Support handoff", systemImage: "bubble.left.and.bubble.right") {
                                Task {
                                    await client.call("workspace_select", ["module": "support.inbox"])
                                    contextualSession = true
                                    preferredColumn = .detail
                                }
                            }
                        }
                    }
                    ForEach(client.modules, id: \.id) { module in
                        Section {
                            Button {
                                Task {
                                    await client.call("workspace_select", ["module": module.id])
                                    contextualSession = false
                                    preferredColumn = .detail
                                }
                            } label: {
                                Label(
                                    module.title,
                                    systemImage: module.id == client.selected ? "checkmark.circle.fill" : "square.grid.2x2"
                                )
                            }
                        } header: {
                            Text(verbatim: module.group)
                        }
                    }
                }
                .navigationTitle("Preview")
            } detail: {
                VStack(spacing: 0) {
                    HStack {
                        Label("Local workspace preview", systemImage: "testtube.2")
                            .font(.caption.bold())
                        Spacer()
                        if client.connected {
                            Button("Disconnect") { Task { await client.call("workspace_disconnect") } }
                        }
                    }
                    .padding().background(.yellow.opacity(0.15))
                    if client.connected, let module = client.modules.first(where: { $0.id == client.selected }) {
                        WorkspaceModuleSurface(
                            source: contextualSession ? sessionSource : module.source,
                            state: client.renderState,
                            command: { try await client.command($0, module: module.id) },
                            failure: { client.rendererFailed = true }
                        )
                        .id(client.renderRevision)
                        .disabled(client.busy)
                        .overlay {
                            if client.busy { ProgressView("Loading workspace…").padding().background(.regularMaterial) }
                            if client.rendererFailed {
                                VStack {
                                    Text("The workspace module could not be rendered.")
                                    Button("Reload workspace") { Task { await client.connect() } }
                                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                            }
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Workspace disconnected", systemImage: "network.slash")
                        } description: {
                            Text(verbatim: client
                                .error ??
                                String(
                                    localized: "This preview uses only an explicit local connection. No saved identity is used."
                                ))
                        } actions: {
                            Button("Connect local workspace") { Task { await client.connect() } }.disabled(client.busy)
                        }
                        if client.busy { ProgressView("Loading workspace…") }
                    }
                }
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
            }
            .task { await client.connect() }
        }

        /// The fixture session and its typed reference ship with the simulator
        /// host, rather than accepting executable session UI from model output.
        private var sessionSource: String {
            Bundle.main.url(forResource: "session-bundle", withExtension: "js")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        }
    }

    @MainActor @Observable
    private final class WorkspacePreviewClient {
        struct Module {
            let id: String
            let title: String
            let group: String
            let source: String
        }

        var modules: [Module] = []
        var selected: String?
        var connected = false
        var title = ""
        var error: String?
        var busy = false
        var rendererFailed = false
        var renderRevision = 0
        var renderState = "{}"
        @ObservationIgnored private let host = NativeHost(httpOnly: true)
        @ObservationIgnored private let queue = DispatchQueue(label: "dev.tuist.luft.workspace", qos: .userInitiated)

        func connect() async {
            let environment = ProcessInfo.processInfo.environment
            await call("workspace_connect", [
                "url": environment["LUFT_WORKSPACE_URL"] ?? "",
                "token": environment["LUFT_WORKSPACE_TOKEN"] ?? "",
            ])
        }

        /// The module cannot select connections, supply authorization, choose an
        /// origin, or invoke production operations. Rust checks declared names.
        func command(_ data: Any?, module: String) async throws -> Any? {
            guard let data = data as? [String: Any], let kind = data["kind"] as? String else {
                throw AppClientError(message: "Invalid workspace command")
            }
            var args: [String: Any] = ["module": module]
            let operation: String
            switch kind {
            case "open":
                operation = "workspace_open"
                args["model"] = data["model"]
                args["id"] = data["id"]
            case "query":
                operation = "workspace_query"
                args["query"] = data["name"]
                args["input"] = data["input"]
            case "action":
                operation = "workspace_action"
                args["action"] = data["name"]
                args["input"] = data["input"]
                args["request_id"] = UUID().uuidString.lowercased()
            case "retry": operation = "workspace_retry"
            default: throw AppClientError(message: "Invalid workspace command")
            }
            let response = await call(operation, args)
            if let error = response["error"] as? String { throw AppClientError(message: error) }
            return response["data"]
        }

        @discardableResult
        func call(_ operation: String, _ args: [String: Any] = [:]) async -> [String: Any] {
            guard !busy else { return ["error": "A workspace request is already in progress"] }
            busy = true
            defer { busy = false }
            do {
                let input = try JSONSerialization.data(withJSONObject: ["operation": operation, "args": args])
                let host = host
                let output: Data = try await withCheckedThrowingContinuation { continuation in
                    queue.async {
                        let pointer = String(decoding: input, as: UTF8.self).withCString { request in
                            tuist_app_call(request, { action, context in
                                guard let action, let context else { return nil }
                                return Unmanaged<NativeHost>.fromOpaque(context).takeUnretainedValue()
                                    .perform(String(cString: action))
                            }, Unmanaged.passUnretained(host).toOpaque())
                        }
                        guard let pointer else {
                            continuation.resume(throwing: AppClientError(message: "Workspace core unavailable"))
                            return
                        }
                        let output = Data(String(cString: pointer).utf8)
                        tuist_app_free(pointer)
                        continuation.resume(returning: output)
                    }
                }
                let response = try JSONSerialization.jsonObject(with: output) as? [String: Any] ?? [:]
                let view = response["view"] as? [String: Any] ?? [:]
                connected = view["connected"] as? Bool ?? false
                title = view["title"] as? String ?? ""
                selected = view["selected"] as? String
                modules = (view["modules"] as? [[String: Any]] ?? []).compactMap { module in
                    guard let id = module["id"] as? String, let title = module["title"] as? String,
                          let group = module["group"] as? String, let source = module["source"] as? String else { return nil }
                    return Module(id: id, title: title, group: group, source: source)
                }
                error = response["error"] as? String
                let state: [String: Any] = [
                    "items": view["items"] ?? NSNull(),
                    "record": view["record"] ?? NSNull(),
                    "error": error as Any? ?? NSNull(),
                    "warning": view["warning"] ?? NSNull(),
                    "can_retry": view["can_retry"] ?? false,
                ]
                renderState = String(
                    decoding: try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
                    as: UTF8.self
                )
                rendererFailed = false
                if operation == "workspace_connect" || operation == "workspace_select" { renderRevision += 1 }
                return response
            } catch {
                connected = false
                modules = []
                selected = nil
                renderState = "{}"
                self.error = String(localized: "The workspace connection failed. Reconnect explicitly to continue.")
                return ["error": self.error ?? "Workspace unavailable"]
            }
        }
    }

#endif
