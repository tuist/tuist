import SwiftUI

public struct ServerSettingsView: View {
    @ObservedObject private var authenticationService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @State private var serverURLString: String
    @State private var errorMessage: String?

    public init(authenticationService: AuthenticationService) {
        self.authenticationService = authenticationService
        _serverURLString = State(initialValue: authenticationService.serverURL.absoluteString)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server address", text: $serverURLString)
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                        .autocorrectionDisabled()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Use the root address of your Tuist server.")
                }

                Section {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }

                    Button("Use default server") {
                        Task {
                            await reset()
                        }
                    }
                    .disabled(!authenticationService.isUsingCustomServerURL)
                }
            }
            .navigationTitle("Server")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 240)
        #endif
        .onReceive(authenticationService.$serverURL) { serverURL in
            serverURLString = serverURL.absoluteString
        }
    }

    @MainActor
    private func save() async {
        do {
            try await authenticationService.updateServerURL(serverURLString)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reset() async {
        do {
            try await authenticationService.resetServerURL()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
