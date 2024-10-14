import Command
import Foundation
import Mockable
import Path
import TuistSupportTesting
import XCTest

@testable import TuistAutomation

final class DeviceControllerTests: TuistUnitTestCase {
    private var subject: DeviceController!
    private var commandRunner: MockCommandRunning!

    override func setUp() {
        super.setUp()

        commandRunner = MockCommandRunning()
        subject = DeviceController(
            commandRunner: commandRunner
        )
    }

    override func tearDown() {
        commandRunner = nil
        subject = nil

        super.tearDown()
    }

    func test_findAvailableDevices() async throws {
        // Given
        var devicesListOutputPath: AbsolutePath?

        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willProduce { arguments, _, _ in
                XCTAssertEqual(
                    [
                        "/usr/bin/xcrun", "devicectl",
                        "list", "devices",
                        "--json-output",
                    ],
                    arguments.dropLast()
                )

                devicesListOutputPath = try? arguments.last.map { try AbsolutePath(validating: $0) }

                if let devicesListOutputPath {
                    let semaphore = DispatchSemaphore(value: 0)
                    Task {
                        try await self.fileSystem.writeText(self.devicesOutputJSON, at: devicesListOutputPath)
                        semaphore.signal()
                    }
                    semaphore.wait()
                }

                return .init(
                    unfolding: {
                        nil
                    }
                )
            }

        // When
        let got = try await subject.findAvailableDevices()

        // Then
        XCTAssertEqual(
            [
                PhysicalDevice(
                    id: "00008027-0018084C1122002E",
                    name: "Marek iPad",
                    platform: .iOS,
                    osVersion: "17.6.1"
                ),
                PhysicalDevice(
                    id: "00008120-001109881103C01E",
                    name: "Marek\'s iPhone",
                    platform: .iOS,
                    osVersion: "17.6.1"
                ),
                PhysicalDevice(
                    id: "00008301-F856EAF4350DA92F",
                    name: "My Watch",
                    platform: .watchOS,
                    osVersion: nil
                ),
            ],
            got
        )
    }

    func test_findAvailableDevices_when_list_decode_failed() async throws {
        // Given
        var devicesListOutputPath: AbsolutePath?

        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willProduce { arguments, _, _ in
                XCTAssertEqual(
                    [
                        "/usr/bin/xcrun", "devicectl",
                        "list", "devices",
                        "--json-output",
                    ],
                    arguments.dropLast()
                )

                devicesListOutputPath = try? arguments.last.map { try AbsolutePath(validating: $0) }

                if let devicesListOutputPath {
                    let semaphore = DispatchSemaphore(value: 0)
                    Task {
                        try await self.fileSystem.writeText("", at: devicesListOutputPath)
                        semaphore.signal()
                    }
                    semaphore.wait()
                }

                return .init(
                    unfolding: {
                        nil
                    }
                )
            }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.findAvailableDevices(),
            DeviceControllerError.listDecodeFailed
        )
    }

    func test_installApp() async throws {
        // Given
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(
                .init(
                    unfolding: {
                        nil
                    }
                )
            )

        let appPath = try temporaryPath()

        // When
        try await subject.installApp(
            at: appPath,
            device: .test(id: "iphone-id")
        )

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/usr/bin/xcrun", "devicectl",
                        "device", "install", "app",
                        "--device", "iphone-id",
                        appPath.pathString,
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    func test_installApp_when_app_verification_failed() async throws {
        // Given
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(
                .init(
                    unfolding: {
                        throw CommandError.terminated(1, stderr: "ApplicationVerificationFailed")
                    }
                )
            )

        let appPath = try temporaryPath()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.installApp(
                at: appPath,
                device: .test(id: "iphone-id")
            ),
            DeviceControllerError.applicationVerificationFailed
        )
    }

    func test_launchApp() async throws {
        // Given
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(
                .init(
                    unfolding: {
                        nil
                    }
                )
            )

        // When
        try await subject.launchApp(
            bundleId: "bundle-id",
            device: .test(id: "iphone-id")
        )

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/usr/bin/xcrun", "devicectl",
                        "device", "process", "launch",
                        "--device", "iphone-id",
                        "bundle-id",
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    private let devicesOutputJSON = """
    {
      "info" : {
        "arguments" : [
          "devicectl",
          "list",
          "devices",
          "--json-output",
          "devices.json"
        ],
        "commandType" : "devicectl.list.devices",
        "environment" : {
          "TERM" : "xterm-256color"
        },
        "jsonVersion" : 2,
        "outcome" : "success",
        "version" : "397.21"
      },
      "result" : {
        "devices" : [
          {
            "capabilities" : [
              {
                "featureIdentifier" : "com.apple.coredevice.feature.connectdevice",
                "name" : "Connect to Device"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.acquireusageassertion",
                "name" : "Acquire Usage Assertion"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.unpairdevice",
                "name" : "Unpair Device"
              }
            ],
            "connectionProperties" : {
              "authenticationType" : "manualPairing",
              "isMobileDeviceOnly" : false,
              "lastConnectionDate" : "2024-09-27T15:49:28.109Z",
              "pairingState" : "paired",
              "potentialHostnames" : [
                "00008027-0018084C1122002E.coredevice.local",
                "016EA1C4-4F90-49AD-9B44-4A82135145BF.coredevice.local"
              ],
              "transportType" : "localNetwork",
              "tunnelState" : "disconnected",
              "tunnelTransportProtocol" : "tcp"
            },
            "deviceProperties" : {
              "ddiServicesAvailable" : false,
              "developerModeStatus" : "enabled",
              "hasInternalOSBuild" : false,
              "name" : "Marek iPad",
              "osBuildUpdate" : "21G93",
              "osVersionNumber" : "17.6.1"
            },
            "hardwareProperties" : {
              "cpuType" : {
                "name" : "arm64e",
                "subType" : 2,
                "type" : 16777228
              },
              "deviceType" : "iPad",
              "ecid" : 6764522239033390,
              "hardwareModel" : "J317AP",
              "isProductionFused" : true,
              "marketingName" : "iPad Pro (11-inch)",
              "platform" : "iOS",
              "productType" : "iPad8,1",
              "reality" : "physical",
              "serialNumber" : "DMPXMC9TKD6J",
              "supportedDeviceFamilies" : [
                1,
                2
              ],
              "thinningProductType" : "iPad8,1",
              "udid" : "00008027-0018084C1122002E"
            },
            "identifier" : "016EA1C4-4F90-49AD-9B44-4A82135145BF",
            "tags" : [

            ],
            "visibilityClass" : "default"
          },
          {
            "capabilities" : [
              {
                "featureIdentifier" : "com.apple.coredevice.feature.unpairdevice",
                "name" : "Unpair Device"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.acquireusageassertion",
                "name" : "Acquire Usage Assertion"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.connectdevice",
                "name" : "Connect to Device"
              }
            ],
            "connectionProperties" : {
              "authenticationType" : "manualPairing",
              "isMobileDeviceOnly" : false,
              "lastConnectionDate" : "2024-09-27T16:46:54.036Z",
              "pairingState" : "paired",
              "potentialHostnames" : [
                "00008120-001109881103C01E.coredevice.local",
                "E5E85238-76F2-4F59-A60F-0B4D08F33764.coredevice.local"
              ],
              "transportType" : "localNetwork",
              "tunnelState" : "disconnected",
              "tunnelTransportProtocol" : "tcp"
            },
            "deviceProperties" : {
              "bootedFromSnapshot" : true,
              "bootedSnapshotName" : "com.apple.os.update-84911EFD055ED880D40F210F193951EDAF7AF320BD9674A7A5E7BF6F3FFE1410",
              "ddiServicesAvailable" : false,
              "developerModeStatus" : "enabled",
              "hasInternalOSBuild" : false,
              "name" : "Marek's iPhone",
              "osBuildUpdate" : "21G93",
              "osVersionNumber" : "17.6.1",
              "rootFileSystemIsWritable" : false
            },
            "hardwareProperties" : {
              "cpuType" : {
                "name" : "arm64e",
                "subType" : 2,
                "type" : 16777228
              },
              "deviceType" : "iPhone",
              "ecid" : 4795554609741854,
              "hardwareModel" : "D73AP",
              "internalStorageCapacity" : 128000000000,
              "isProductionFused" : true,
              "marketingName" : "iPhone 14 Pro",
              "platform" : "iOS",
              "productType" : "iPhone15,2",
              "reality" : "physical",
              "serialNumber" : "L6K3V77N1V",
              "supportedCPUTypes" : [
                {
                  "name" : "arm64e",
                  "subType" : 2,
                  "type" : 16777228
                },
                {
                  "name" : "arm64",
                  "subType" : 0,
                  "type" : 16777228
                },
                {
                  "name" : "arm64",
                  "subType" : 1,
                  "type" : 16777228
                },
                {
                  "name" : "arm64_32",
                  "subType" : 1,
                  "type" : 33554444
                }
              ],
              "supportedDeviceFamilies" : [
                1
              ],
              "thinningProductType" : "iPhone15,2",
              "udid" : "00008120-001109881103C01E"
            },
            "identifier" : "E5E85238-76F2-4F59-A60F-0B4D08F33764",
            "tags" : [

            ],
            "visibilityClass" : "default"
          },
          {
            "capabilities" : [
              {
                "featureIdentifier" : "com.apple.coredevice.feature.unpairdevice",
                "name" : "Unpair Device"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.connectdevice",
                "name" : "Connect to Device"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.acquireusageassertion",
                "name" : "Acquire Usage Assertion"
              }
            ],
            "connectionProperties" : {
              "authenticationType" : "manualPairing",
              "isMobileDeviceOnly" : false,
              "pairingState" : "paired",
              "potentialHostnames" : [
                "00008301-F856EAF4350DA92F.coredevice.local",
                "497621AE-9F6E-0515-BF34-974F61E542E6.coredevice.local"
              ],
              "transportType" : "localNetwork",
              "tunnelState" : "disconnected",
              "tunnelTransportProtocol" : "tcp"
            },
            "deviceProperties" : {
              "ddiServicesAvailable" : false,
              "name" : "My Watch"
            },
            "hardwareProperties" : {
              "deviceType" : "appleWatch",
              "ecid" : 17819358193419324013,
              "platform" : "watchOS",
              "productType" : "Watch6,15",
              "udid" : "00008301-F856EAF4350DA92F"
            },
            "identifier" : "497621AE-9F6E-0515-BF34-974F61E542E6",
            "tags" : [

            ],
            "visibilityClass" : "default"
          }
        ]
      }
    }
    """
}
