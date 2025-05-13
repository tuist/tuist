import class AppKit.NSPasteboard
import Foundation
import SwiftUI
import TuistAutomation
import TuistCore
import TuistSupport

struct PhysicalDeviceRow: View {
    let device: PhysicalDevice
    let selected: Bool
    let onSelected: (PhysicalDevice) -> Void

    @State var viewModel = SimulatorRowViewModel()
    @State private var highlighted = false

    private func deviceImage() -> some View {
        switch device.platform {
        case .iOS:
            if device.name.contains("iPad") {
                Image(systemName: "ipad")
            } else {
                Image(systemName: "iphone")
            }
        case .visionOS:
            Image(systemName: "visionpro")
        case .tvOS:
            Image(systemName: "tv")
        case .macOS:
            Image(systemName: "macbook")
        case .watchOS:
            Image(systemName: "applewatch")
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                Circle()
                    .fill(selected ? .blue : .gray.opacity(0.4))

                deviceImage()
                    .foregroundColor(
                        selected ? TuistMenuBarAsset.Assets.light.swiftUIColor : TuistMenuBarAsset.Assets.dark
                            .swiftUIColor
                    )
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading) {
                Text(device.name)
                    .font(.title3)
                device.osVersion.map { Text($0) }
            }
            Spacer()

            Group {
                switch device.transportType {
                case .wifi:
                    Image(systemName: "network")
                case .usb, .none:
                    EmptyView()
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .menuItemStyle()
        .onTapGesture {
            onSelected(device)
        }
    }
}
