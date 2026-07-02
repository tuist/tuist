import Foundation
import Path
import Testing

@testable import TuistKit

#if canImport(TuistCacheEE)
    struct CacheWarmCommandServiceTests {
        @Test func returns_empty_when_all_required_slices_are_present() throws {
            // Given
            let simulator = try AbsolutePath(validating: "/artifacts/iOS/simulator")
            let device = try AbsolutePath(validating: "/artifacts/iOS/device")

            // When
            let got = CacheWarmCommandService.missingRequiredXCFrameworkSlices(
                expectedSliceDirectories: [simulator, device],
                resolvedSliceDirectories: [simulator, device]
            )

            // Then
            #expect(got == [])
        }

        @Test func returns_the_missing_primary_slice() throws {
            // Given
            let simulator = try AbsolutePath(validating: "/artifacts/iOS/simulator")
            let device = try AbsolutePath(validating: "/artifacts/iOS/device")

            // When the simulator build silently produced nothing
            let got = CacheWarmCommandService.missingRequiredXCFrameworkSlices(
                expectedSliceDirectories: [simulator, device],
                resolvedSliceDirectories: [device]
            )

            // Then
            #expect(got == [simulator])
        }

        @Test func treats_mac_catalyst_slice_as_optional() throws {
            // Given
            let simulator = try AbsolutePath(validating: "/artifacts/iOS/simulator")
            let device = try AbsolutePath(validating: "/artifacts/iOS/device")
            let macCatalyst = try AbsolutePath(validating: "/artifacts/iOS/mac-catalyst")

            // When a target builds for simulator and device but isn't Catalyst-compatible
            let got = CacheWarmCommandService.missingRequiredXCFrameworkSlices(
                expectedSliceDirectories: [simulator, device, macCatalyst],
                resolvedSliceDirectories: [simulator, device]
            )

            // Then
            #expect(got == [])
        }

        @Test func reports_missing_primary_slice_even_when_mac_catalyst_is_present() throws {
            // Given
            let simulator = try AbsolutePath(validating: "/artifacts/iOS/simulator")
            let device = try AbsolutePath(validating: "/artifacts/iOS/device")
            let macCatalyst = try AbsolutePath(validating: "/artifacts/iOS/mac-catalyst")

            // When the device build silently produced nothing but Catalyst succeeded
            let got = CacheWarmCommandService.missingRequiredXCFrameworkSlices(
                expectedSliceDirectories: [simulator, device, macCatalyst],
                resolvedSliceDirectories: [simulator, macCatalyst]
            )

            // Then
            #expect(got == [device])
        }

        @Test func reports_missing_slice_for_any_supported_platform() throws {
            // Given a target supporting iOS and macOS (macOS has no simulator slice)
            let iosSimulator = try AbsolutePath(validating: "/artifacts/iOS/simulator")
            let iosDevice = try AbsolutePath(validating: "/artifacts/iOS/device")
            let macOSDevice = try AbsolutePath(validating: "/artifacts/macOS/device")

            // When the macOS build silently produced nothing
            let got = CacheWarmCommandService.missingRequiredXCFrameworkSlices(
                expectedSliceDirectories: [iosSimulator, iosDevice, macOSDevice],
                resolvedSliceDirectories: [iosSimulator, iosDevice]
            )

            // Then
            #expect(got == [macOSDevice])
        }
    }
#endif
