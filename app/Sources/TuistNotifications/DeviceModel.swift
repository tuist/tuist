import Foundation
import UIKit

/// The marketing name of the device model, for example "iPhone 17 Pro". `UIDevice.current.name` is generic on modern iOS.
enum DeviceModel {
    @MainActor
    static var name: String {
        names[identifier] ?? UIDevice.current.model
    }

    static var identifier: String {
        if let simulatorIdentifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatorIdentifier
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
    }

    static let names: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone18,5": "iPhone 17e",
        "iPhone19,2": "iPhone 18 Pro",
        "iPhone19,3": "iPhone 18 Pro Max",
        "iPhone19,7": "iPhone 18 Pro Max",
        "iPad13,18": "iPad (10th generation)",
        "iPad13,19": "iPad (10th generation)",
        "iPad15,7": "iPad (A16)",
        "iPad15,8": "iPad (A16)",
        "iPad14,1": "iPad mini (6th generation)",
        "iPad14,2": "iPad mini (6th generation)",
        "iPad16,1": "iPad mini (A17 Pro)",
        "iPad16,2": "iPad mini (A17 Pro)",
        "iPad13,16": "iPad Air (5th generation)",
        "iPad13,17": "iPad Air (5th generation)",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)",
        "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad15,3": "iPad Air 11-inch (M3)",
        "iPad15,4": "iPad Air 11-inch (M3)",
        "iPad15,5": "iPad Air 13-inch (M3)",
        "iPad15,6": "iPad Air 13-inch (M3)",
        "iPad16,8": "iPad Air 11-inch (M4)",
        "iPad16,9": "iPad Air 11-inch (M4)",
        "iPad16,10": "iPad Air 13-inch (M4)",
        "iPad16,11": "iPad Air 13-inch (M4)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)",
        "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        "iPad17,1": "iPad Pro 11-inch (M5)",
        "iPad17,2": "iPad Pro 11-inch (M5)",
        "iPad17,3": "iPad Pro 13-inch (M5)",
        "iPad17,4": "iPad Pro 13-inch (M5)",
    ]
}
