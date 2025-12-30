import Command
import Foundation
import Mockable
import Path
import TuistTesting
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

                return self.write(text: self.devicesOutputJSON, at: arguments.last!)
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
                    osVersion: "17.6.1",
                    transportType: .wifi,
                    connectionState: .disconnected
                ),
                PhysicalDevice(
                    id: "00008120-001109881103C01E",
                    name: "Marek\'s iPhone",
                    platform: .iOS,
                    osVersion: "17.6.1",
                    transportType: .wifi,
                    connectionState: .disconnected
                ),
                PhysicalDevice(
                    id: "00008132-0103524335E2F624",
                    name: "My iPhone",
                    platform: .iOS,
                    osVersion: "17.3.1",
                    transportType: .usb,
                    connectionState: .connected
                ),
                PhysicalDevice(
                    id: "00008301-F856EAF4350DA92F",
                    name: "My Watch",
                    platform: .watchOS,
                    osVersion: nil,
                    transportType: .wifi,
                    connectionState: .disconnected
                ),
                PhysicalDevice(
                    id: "00008120-A9123890F89EA35B",
                    name: "My Watch S8",
                    platform: .watchOS,
                    osVersion: "11.0.1",
                    transportType: nil,
                    connectionState: .disconnected
                ),
            ],
            got
        )
    }

    func test_findAvailableDevices_when_fetching_devices_failed() async throws {
        // Given
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willProduce { arguments, _, _ in
                self.write(text: "", at: arguments.last!)
            }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.findAvailableDevices(),
            DeviceControllerError.fetchingDevicesFailed
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

    private func write<Element>(text: String, at path: String) -> AsyncThrowingStream<Element, any Error> {
        guard let outputPath = try? AbsolutePath(validating: path) else {
            return .init(unfolding: { nil })
        }
        return .init(
            unfolding: {
                try await self.fileSystem.writeText(text, at: outputPath)
                return nil
            }
        )
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
                "featureIdentifier" : "com.apple.coredevice.feature.tags",
                "name" : "Modify Tags"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.default.user.credentials",
                "name" : "Modify credentials for default users for a device"
              }
            ],
            "connectionProperties" : {
              "isMobileDeviceOnly" : false,
              "pairingState" : "unsupported",
              "potentialHostnames" : [
                "67946E7A-2A5D-5B91-9E34-ECD8AC0E4D09.coredevice.local"
              ],
              "tunnelState" : "unavailable"
            },
            "deviceProperties" : {
              "bootState" : "booted",
              "ddiServicesAvailable" : false
            },
            "hardwareProperties" : {

            },
            "identifier" : "67946E7A-2A5D-5B91-9E34-ECD8AC0E4D09",
            "tags" : [

            ],
            "visibilityClass" : "default"
          },
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
                "featureIdentifier" : "com.apple.coredevice.feature.capturesysdiagnose",
                "name" : "Capture Sysdiagnose"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.fetchddimetadata",
                "name" : "Fetch Developer Disk Image Services Metadata"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.sendsignaltoprocess",
                "name" : "Send Signal to Process"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.querymobilegestalt",
                "name" : "Query MobileGestalt"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.monitorprocesstermination",
                "name" : "Monitor Process for Termination"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.fetchappicons",
                "name" : "Fetch Application Icons"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.rebootdevice",
                "name" : "Reboot Device"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.spawnexecutable",
                "name" : "Spawn Executable"
              },
              {
                "featureIdentifier" : "com.apple.dt.remoteFetchSymbols.dyldSharedCacheFiles",
                "name" : "com.apple.dt.remoteFetchSymbols"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.transferFiles",
                "name" : "Transfer Files"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.disconnectdevice",
                "name" : "Disconnect from Device"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.installroot",
                "name" : "Install Root"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.listapps",
                "name" : "List Applications"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.installapp",
                "name" : "Install Application"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.listroots",
                "name" : "List Roots"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.sendmemorywarningtoprocess",
                "name" : "Send Memory Warning to Process"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.getdeviceinfo",
                "name" : "Fetch Extended Device Info"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.acquireusageassertion",
                "name" : "Acquire Usage Assertion"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.uninstallroot",
                "name" : "Uninstall Root"
              },
              {
                "featureIdentifier" : "com.apple.dt.profile",
                "name" : "Service Hub Profile"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.getlockstate",
                "name" : "Get Lock State"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.disableddiservices",
                "name" : "Disable Developer Disk Image Services"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.launchapplication",
                "name" : "Launch Application"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.viewdevicescreen",
                "name" : "View Device Screen"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.listprocesses",
                "name" : "List Processes"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.debugserverproxy",
                "name" : "com.apple.internal.dt.remote.debugproxy"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.getdisplayinfo",
                "name" : "Get Display Information"
              },
              {
                "featureIdentifier" : "com.apple.coredevice.feature.uninstallapp",
                "name" : "Uninstall Application"
              }
            ],
            "connectionProperties" : {
              "authenticationType" : "manualPairing",
              "isMobileDeviceOnly" : false,
              "lastConnectionDate" : "2024-10-17T22:50:28.991Z",
              "localHostnames" : [
                "My-iPhone.coredevice.local",
                "00008132-0103524335E2F624.coredevice.local",
                "7F6E5352-0E68-3152-A82F-89CF6EDA9531E.coredevice.local"
              ],
              "pairingState" : "paired",
              "potentialHostnames" : [
                "00008132-0103524335E2F624.coredevice.local",
                "7F6E5352-0E68-3152-A82F-89CF6EDA9531E.coredevice.local"
              ],
              "transportType" : "wired",
              "tunnelIPAddress" : "fa42:7efa:3e2f::1",
              "tunnelState" : "connected",
              "tunnelTransportProtocol" : "tcp"
            },
            "deviceProperties" : {
              "bootedFromSnapshot" : true,
              "bootedSnapshotName" : "com.apple.os.update-9898FE99999900120346FF9F8EA12E00F9898FE99999900120346FF9F8EA12E00FE089892190FE89A890809809FE9E0A",
              "bootState" : "booted",
              "ddiServicesAvailable" : true,
              "developerModeStatus" : "enabled",
              "hasInternalOSBuild" : false,
              "name" : "My iPhone",
              "osBuildUpdate" : "21D61",
              "osVersionNumber" : "17.3.1",
              "rootFileSystemIsWritable" : false,
              "screenViewingURL" : "devices://device/open?id=7F6E5352-0E68-3152-A82F-89CF6EDA9531E"
            },
            "hardwareProperties" : {
              "cpuType" : {
                "name" : "arm64e",
                "subType" : 2,
                "type" : 16777228
              },
              "deviceType" : "iPhone",
              "ecid" : 1992940239409430,
              "hardwareModel" : "N104AP",
              "internalStorageCapacity" : 128000000000,
              "isProductionFused" : true,
              "marketingName" : "iPhone 11",
              "platform" : "iOS",
              "productType" : "iPhone12,1",
              "reality" : "physical",
              "serialNumber" : "A5906FE3A639",
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
              "thinningProductType" : "iPhone12,1",
              "udid" : "00008132-0103524335E2F624"
            },
            "identifier" : "7F6E5352-0E68-3152-A82F-89CF6EDA9531E",
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
          },
          {
            "capabilities" : [
              {
                "featureIdentifier" : "com.apple.coredevice.feature.unpairdevice",
                "name" : "Unpair Device"
              }
            ],
            "connectionProperties" : {
              "authenticationType" : "manualPairing",
              "isMobileDeviceOnly" : false,
              "lastConnectionDate" : "2024-10-12T14:40:44.703Z",
              "pairingState" : "paired",
              "potentialHostnames" : [
                "00008120-A9123890F89EA35B.coredevice.local",
                "890F8E81-A295-89D1-AF02-9F890A89089E.coredevice.local"
              ],
              "tunnelState" : "unavailable"
            },
            "deviceProperties" : {
              "ddiServicesAvailable" : false,
              "developerModeStatus" : "disabled",
              "hasInternalOSBuild" : false,
              "name" : "My Watch S8",
              "osBuildUpdate" : "22R361",
              "osVersionNumber" : "11.0.1"
            },
            "hardwareProperties" : {
              "cpuType" : {
                "name" : "arm64_32",
                "subType" : 1,
                "type" : 33554444
              },
              "deviceType" : "appleWatch",
              "ecid" : 17129084317543758948,
              "hardwareModel" : "N197bAP",
              "isProductionFused" : true,
              "marketingName" : "Apple Watch Series 8",
              "platform" : "watchOS",
              "productType" : "Watch6,15",
              "reality" : "physical",
              "serialNumber" : "K29F36127F",
              "thinningProductType" : "Watch6,15",
              "udid" : "00008120-A9123890F89EA35B"
            },
            "identifier" : "890F8E81-A295-89D1-AF02-9F890A89089E",
            "tags" : [

            ],
            "visibilityClass" : "default"
          }
        ]
      }
    }
    """
}
