import AppKit
import Combine
import Foundation
import Sparkle
import SwiftUI
import TuistAuthentication
import TuistServer

@MainActor
public final class MacApplicationModel: ObservableObject {
    let authenticationService: AuthenticationService
    let deviceService: DeviceService
    let taskStatusReporter = TaskStatusReporter()
    let errorHandling = ErrorHandling()
    @Published private(set) var canCheckForUpdates = false
    private let updater: SPUUpdater
    private var cancellables = Set<AnyCancellable>()
    private var isObservingURLs = false
    private var deviceLoadingTask: Task<Void, Error>?

    public init(updaterController: SPUStandardUpdaterController) {
        authenticationService = MacApplicationEnvironment.withValue { AuthenticationService() }
        deviceService = DeviceService(taskStatusReporter: taskStatusReporter)
        updater = updaterController.updater
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    public func observeURLs(from appDelegate: AppDelegate) {
        guard !isObservingURLs else { return }
        isObservingURLs = true
        appDelegate.onChangeOfURLs.sink { [weak self, weak appDelegate] urls in
            guard let self else { return }
            for url in urls where Self.isPreviewDeepLink(url) {
                appDelegate?.openMainWindow?()
                errorHandling.fireAndHandleError {
                    try await self.loadDevices()
                    try await self.deviceService.launchPreviewDeeplink(with: url)
                }
            }
        }
        .store(in: &cancellables)
    }

    static func isPreviewDeepLink(_ url: URL) -> Bool {
        url.scheme == "tuist" && (url.host == "open-preview" || url.path == "open-preview")
    }

    func loadDevices() async throws {
        if let deviceLoadingTask {
            return try await deviceLoadingTask.value
        }
        let task = Task { try await deviceService.loadDevices() }
        deviceLoadingTask = task
        do {
            try await task.value
        } catch {
            deviceLoadingTask = nil
            throw error
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

enum MacApplicationEnvironment {
    private static let credentialsStore = ServerCredentialsStore(backend: .keychain)
    private static let cachedValueStore = CachedValueStore(backend: .inSystemProcess)

    static func withValue<T>(_ action: () throws -> T) rethrows -> T {
        try ServerCredentialsStore.$current.withValue(credentialsStore) {
            try CachedValueStore.$current.withValue(cachedValueStore, operation: action)
        }
    }

    static func withValue<T>(_ action: () async throws -> T) async rethrows -> T {
        try await ServerCredentialsStore.$current.withValue(credentialsStore) {
            try await CachedValueStore.$current.withValue(cachedValueStore, operation: action)
        }
    }
}

extension View {
    func macApplicationEnvironment(_ model: MacApplicationModel) -> some View {
        environmentObject(model.authenticationService)
            .environmentObject(model.deviceService)
            .environmentObject(model.taskStatusReporter)
            .environmentObject(model.errorHandling)
    }
}
