#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Testing

    @testable import TuistServer

    @Suite(.serialized)
    struct AppCredentialStoreTests {
        private let serverURL = URL(string: "https://Tuist.Dev.")!

        @Test(.inTemporaryDirectory) func later_task_keeps_app_credentials_out_of_the_cli_file() async throws {
            let root = try #require(FileSystem.temporaryTestDirectory)
            let fileSystem = FileSystem()
            let cliDirectory = root.appending(component: "cli")
            let appDirectory = root.appending(component: "app")
            try await fileSystem.makeDirectory(at: cliDirectory)
            try await fileSystem.makeDirectory(at: appDirectory)
            let cliStore = ServerCredentialsStore(backend: .fileSystem, configDirectory: cliDirectory)
            let appStore = ServerCredentialsStore(backend: .fileSystem, configDirectory: appDirectory)
            let appCredentials = ServerCredentials(accessToken: "app-token", refreshToken: "app-refresh")
            let cliCredentials = ServerCredentials(accessToken: "cli-token", refreshToken: "cli-refresh")

            try await withUnboundCredentialsStore(appStore) {
                ServerCredentialsStore.$current.withValue(cliStore) {}

                try await Task {
                    try await ServerCredentialsStore.current.store(credentials: appCredentials, serverURL: serverURL)
                }.value

                #expect(try await appStore.read(serverURL: serverURL) == appCredentials)
                #expect(try await cliStore.read(serverURL: serverURL) == nil)

                try await ServerCredentialsStore.$current.withValue(cliStore) {
                    try await ServerCredentialsStore.current.store(credentials: cliCredentials, serverURL: serverURL)
                }

                #expect(try await cliStore.read(serverURL: serverURL) == cliCredentials)
                #expect(try await appStore.read(serverURL: serverURL) == appCredentials)
            }
        }

        @Test(.inTemporaryDirectory) func refresh_lock_key_follows_the_active_store() async throws {
            let directory = try #require(FileSystem.temporaryTestDirectory)
            let cliStore = ServerCredentialsStore(backend: .fileSystem, configDirectory: directory)
            let keychainStore = ServerCredentialsStore(backend: .keychain)

            try await withUnboundCredentialsStore(keychainStore) {
                let installed = ServerCredentialsStore.installAppKeychainStore()
                #expect(try installed.storageKey(serverURL: serverURL) == "https://tuist.dev")
                #expect(try credentialRefreshStorageKey(serverURL: serverURL) == "https://tuist.dev")
                #expect(try keychainStore.storageKey(serverURL: serverURL) == "https://tuist.dev")

                try await ServerCredentialsStore.$current.withValue(cliStore) {
                    let key = try credentialRefreshStorageKey(serverURL: serverURL)
                    #expect(key == (try cliStore.storageKey(serverURL: serverURL)))
                    #expect(key.hasSuffix("credentials/tuist.dev.json"))
                }
            }
        }
    }
#endif
