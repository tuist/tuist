import Foundation
import MachO
import StoreKit
import UIKit

/// TuistSDK provides automatic update checking for Tuist Preview builds.
///
/// Use this SDK in apps distributed via Tuist Previews to detect when a newer
/// version is available on the same track (git branch).
///
/// Example usage:
/// ```swift
/// struct MyApp: App {
///     private let tuistSDK = TuistSDK(
///         fullHandle: "myorg/myapp",
///         apiKey: "your-api-key"
///     )
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .onAppear {
///                     // Uses default alert UI
///                     tuistSDK.startUpdateChecking()
///
///                     // Or with custom handler:
///                     // tuistSDK.startUpdateChecking { updateInfo in
///                     //     print("Update available: \(updateInfo.version ?? "unknown")")
///                     // }
///                 }
///         }
///     }
/// }
/// ```
@MainActor
public final class TuistSDK {
    /// The Tuist server URL.
    public let serverURL: URL

    /// The full handle in the format "account-handle/project-handle".
    public let fullHandle: String

    /// The account handle extracted from fullHandle.
    public let accountHandle: String

    /// The project handle extracted from fullHandle.
    public let projectHandle: String

    /// The API key (account token) for authentication.
    public let apiKey: String

    /// The interval between update checks. Default is 600 seconds (10 minutes).
    public let checkInterval: TimeInterval

    private var updateCallback: ((PreviewUpdateInfo) -> Void)?
    private var checkTimer: Timer?
    private let currentBinaryId: String?

    /// Creates a new TuistSDK instance.
    ///
    /// - Parameters:
    ///   - fullHandle: The full handle in the format "account-handle/project-handle".
    ///   - apiKey: The API key (account token) for authentication.
    ///   - serverURL: The Tuist server URL. Defaults to https://tuist.dev
    ///   - checkInterval: The interval between update checks. Default is 600 seconds (10 minutes).
    public init(
        fullHandle: String,
        apiKey: String,
        serverURL: URL = URL(string: "https://tuist.dev")!,
        checkInterval: TimeInterval = 600
    ) {
        let components = fullHandle.components(separatedBy: "/")
        guard components.count == 2 else {
            preconditionFailure(
                "The project full handle \(fullHandle) is not in the format of account-handle/project-handle."
            )
        }

        self.serverURL = serverURL
        self.fullHandle = fullHandle
        self.accountHandle = components[0]
        self.projectHandle = components[1]
        self.apiKey = apiKey
        self.checkInterval = checkInterval
        self.currentBinaryId = Self.extractBinaryId()
    }

    /// Starts periodic update checking.
    ///
    /// - Parameter onUpdateAvailable: Called on the main thread when an update is available.
    ///   If not provided, a default alert will be shown with options to cancel or install the update.
    ///
    /// - Note: Update checking is disabled on simulators and App Store builds.
    public func startUpdateChecking(onUpdateAvailable: ((PreviewUpdateInfo) -> Void)? = nil) {
        #if targetEnvironment(simulator)
            // Don't run on simulators
            return
        #else
            Task {
                // Don't run on App Store builds
                if await isAppStoreBuild() {
                    return
                }

                updateCallback = onUpdateAvailable ?? { [weak self] updateInfo in
                    self?.showDefaultUpdateAlert(updateInfo: updateInfo)
                }

                checkTimer?.invalidate()
                checkTimer = Timer.scheduledTimer(
                    withTimeInterval: checkInterval,
                    repeats: true
                ) { [weak self] _ in
                    Task { @MainActor in
                        await self?.performUpdateCheck()
                    }
                }

                await performUpdateCheck()
            }
        #endif
    }

    private func isAppStoreBuild() async -> Bool {
        guard let appTransaction = try? await AppTransaction.shared else {
            return false
        }
        switch appTransaction {
        case .verified:
            return true
        case .unverified:
            return false
        }
    }

    private func showDefaultUpdateAlert(updateInfo: PreviewUpdateInfo) {
        print("Showing!!")
        let title = "Update Available"
        let message: String
        if let version = updateInfo.version {
            message = "A new version (\(version)) is available. Would you like to install it?"
        } else {
            message = "A new version is available. Would you like to install it?"
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Install", style: .default) { _ in
            UIApplication.shared.open(updateInfo.downloadURL)
        })

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let rootViewController = windowScene.windows.first?.rootViewController
        else {
            return
        }

        var presenter = rootViewController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
    }

    /// Stops periodic update checking.
    public func stopUpdateChecking() {
        checkTimer?.invalidate()
        checkTimer = nil
        updateCallback = nil
    }

    /// Performs a single update check.
    ///
    /// - Returns: Update info if an update is available, nil otherwise.
    public func checkForUpdateNow() async throws -> PreviewUpdateInfo? {
        guard let binaryId = currentBinaryId else {
            throw TuistSDKError.binaryIdNotFound
        }

        return try await checkForUpdate(binaryId: binaryId)
    }

    private func performUpdateCheck() async {
        guard let callback = updateCallback, let binaryId = currentBinaryId else { return }

        do {
            if let updateInfo = try await checkForUpdate(binaryId: binaryId) {
                callback(updateInfo)
            }
        } catch {
            // Silently ignore errors during background checks
        }
    }

    private func checkForUpdate(binaryId: String) async throws -> PreviewUpdateInfo? {
        let url = serverURL
            .appendingPathComponent("api/projects")
            .appendingPathComponent(accountHandle)
            .appendingPathComponent(projectHandle)
            .appendingPathComponent("previews")
            .appendingPathComponent("latest")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "binary_id", value: binaryId),
        ]

        guard let requestURL = components?.url else {
            throw TuistSDKError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TuistSDKError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TuistSDKError.serverError(statusCode: httpResponse.statusCode)
        }

        let latestResponse = try JSONDecoder().decode(LatestPreviewResponse.self, from: data)

        guard let latestPreview = latestResponse.preview else {
            return nil
        }

        // Update available if the latest preview has a different binary ID than the running app
        if latestPreview.binaryId != binaryId {
            return PreviewUpdateInfo(
                previewId: latestPreview.id,
                displayName: latestPreview.displayName,
                version: latestPreview.version,
                bundleIdentifier: latestPreview.bundleIdentifier,
                gitBranch: latestPreview.gitBranch,
                downloadURL: latestPreview.url
            )
        }

        return nil
    }

    private static func extractBinaryId() -> String? {
        for i in 0 ..< _dyld_image_count() {
            guard let header = _dyld_get_image_header(i) else { continue }

            let headerPtr = UnsafeRawPointer(header)

            let is64Bit = header.pointee.magic == MH_MAGIC_64 || header.pointee.magic == MH_CIGAM_64

            var loadCommandPtr: UnsafeRawPointer
            if is64Bit {
                loadCommandPtr = headerPtr.advanced(by: MemoryLayout<mach_header_64>.size)
            } else {
                loadCommandPtr = headerPtr.advanced(by: MemoryLayout<mach_header>.size)
            }

            for _ in 0 ..< header.pointee.ncmds {
                let loadCommand = loadCommandPtr.assumingMemoryBound(to: load_command.self).pointee

                if loadCommand.cmd == LC_UUID {
                    let uuidCommand = loadCommandPtr.assumingMemoryBound(to: uuid_command.self).pointee
                    let uuid = UUID(uuid: uuidCommand.uuid)
                    return uuid.uuidString
                }

                loadCommandPtr = loadCommandPtr.advanced(by: Int(loadCommand.cmdsize))
            }
        }
        return nil
    }
}

/// Errors that can occur when using TuistSDK.
public enum TuistSDKError: LocalizedError {
    case binaryIdNotFound
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .binaryIdNotFound:
            return "Could not extract binary ID from the running executable"
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case let .serverError(statusCode):
            return "Server returned error status code: \(statusCode)"
        }
    }
}

private struct LatestPreviewResponse: Codable {
    let preview: Preview?

    struct Preview: Codable {
        let id: String
        let displayName: String?
        let version: String?
        let bundleIdentifier: String
        let gitBranch: String?
        let binaryId: String?
        let url: URL

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case version
            case bundleIdentifier = "bundle_identifier"
            case gitBranch = "git_branch"
            case binaryId = "binary_id"
            case url
        }
    }
}
