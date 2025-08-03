import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct BundleShowCommandServiceTests {
    private let getBundleService = MockGetBundleServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let subject: BundleShowCommandService!

    init() {
        subject = BundleShowCommandService(
            getBundleService: getBundleService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment()) func run_when_full_handle_is_not_pass_and_absent_in_config() async throws {
        // Given
        let tuist = Tuist.test(fullHandle: nil)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)

        // When
        await #expect(throws: BundleShowServiceError.missingFullHandle, performing: {
            try await subject.run(
                fullHandle: nil,
                bundleId: "bundle-123",
                path: nil,
                json: false
            )
        })
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_not_pass_and_present_in_config_and_not_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let bunldeId = "\(UUID().uuidString).tuist.dev"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let bundle = ServerBundle.test(artifacts: [.test()])
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(getBundleService).getBundle(
            fullHandle: .value(fullHandle),
            bundleId: .value(bunldeId),
            serverURL: .value(serverURL)
        ).willReturn(bundle)
        // When
        try await subject.run(
            fullHandle: nil,
            bundleId: bunldeId,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains(subject.formatBundleInfo(bundle)))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_not_pass_and_present_in_config_and_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let bunldeId = "\(UUID().uuidString).tuist.dev"
        let tuist = Tuist.test(fullHandle: fullHandle)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let bundle = ServerBundle.test(artifacts: [.test()])
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(getBundleService).getBundle(
            fullHandle: .value(fullHandle),
            bundleId: .value(bunldeId),
            serverURL: .value(serverURL)
        ).willReturn(bundle)
        // When
        try await subject.run(
            fullHandle: nil,
            bundleId: bunldeId,
            path: nil,
            json: true
        )

        // Then
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bundleJSON = String(data: try jsonEncoder.encode(bundle), encoding: .utf8)!
        #expect(ui().contains(bundleJSON))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_passed_and_absent_in_config_and_not_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let bunldeId = "\(UUID().uuidString).tuist.dev"
        let tuist = Tuist.test(fullHandle: nil)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let bundle = ServerBundle.test(artifacts: [.test()])
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(getBundleService).getBundle(
            fullHandle: .value(fullHandle),
            bundleId: .value(bunldeId),
            serverURL: .value(serverURL)
        ).willReturn(bundle)
        // When
        try await subject.run(
            fullHandle: fullHandle,
            bundleId: bunldeId,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains(subject.formatBundleInfo(bundle)))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_passed_and_absent_in_config_and_json() async throws {
        // Given
        let fullHandle = "\(UUID().uuidString)/\(UUID().uuidString)"
        let bunldeId = "\(UUID().uuidString).tuist.dev"
        let tuist = Tuist.test(fullHandle: nil)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let bundle = ServerBundle.test(artifacts: [.test()])
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)
        given(getBundleService).getBundle(
            fullHandle: .value(fullHandle),
            bundleId: .value(bunldeId),
            serverURL: .value(serverURL)
        ).willReturn(bundle)
        // When
        try await subject.run(
            fullHandle: fullHandle,
            bundleId: bunldeId,
            path: nil,
            json: true
        )

        // Then
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bundleJSON = String(data: try jsonEncoder.encode(bundle), encoding: .utf8)!
        #expect(ui().contains(bundleJSON))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_passed_and_present_in_config_and_not_json() async throws {
        // Given
        let configFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)-config"
        let optionFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)-option"
        let bunldeId = "\(UUID().uuidString).tuist.dev"
        let tuist = Tuist.test(fullHandle: configFullHandle)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let bundle = ServerBundle.test(artifacts: [.test()])
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        // The full handle passed through CLI args takes precedence
        given(getBundleService).getBundle(
            fullHandle: .value(optionFullHandle),
            bundleId: .value(bunldeId),
            serverURL: .value(serverURL)
        ).willReturn(bundle)
        // When
        try await subject.run(
            fullHandle: optionFullHandle,
            bundleId: bunldeId,
            path: nil,
            json: false
        )

        // Then
        #expect(ui().contains(subject.formatBundleInfo(bundle)))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora
    ) func run_when_full_handle_is_passed_and_present_in_config_and_json() async throws {
        // Given
        let configFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)-config"
        let optionFullHandle = "\(UUID().uuidString)/\(UUID().uuidString)-option"
        let bunldeId = "\(UUID().uuidString).tuist.dev"
        let tuist = Tuist.test(fullHandle: configFullHandle)
        let serverURL = URL(string: "https://\(UUID().uuidString).tuist.dev")!
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let bundle = ServerBundle.test(artifacts: [.test()])
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(tuist)
        given(serverEnvironmentService).url(configServerURL: .value(tuist.url)).willReturn(serverURL)

        // The full handle passed through CLI args takes precedence
        given(getBundleService).getBundle(
            fullHandle: .value(optionFullHandle),
            bundleId: .value(bunldeId),
            serverURL: .value(serverURL)
        ).willReturn(bundle)
        // When
        try await subject.run(
            fullHandle: optionFullHandle,
            bundleId: bunldeId,
            path: nil,
            json: true
        )

        // Then
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bundleJSON = String(data: try jsonEncoder.encode(bundle), encoding: .utf8)!
        #expect(ui().contains(bundleJSON))
    }
}
