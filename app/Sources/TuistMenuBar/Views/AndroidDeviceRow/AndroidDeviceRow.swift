import class AppKit.NSPasteboard
import Foundation
import SwiftUI
import TuistAndroid

struct AndroidDeviceRow: View {
    let device: AndroidDevice
    let selected: Bool
    var pinned: Bool = false
    let onSelected: (AndroidDevice) -> Void
    var onPinned: ((AndroidDevice, Bool) -> Void)?

    @State private var highlighted = false

    private func deviceImage() -> some View {
        switch device.type {
        case .emulator:
            Image(systemName: "iphone")
        case .device:
            Image(systemName: "iphone")
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
                Text(device.type == .emulator ? "Android Emulator" : "Android Device")
            }
            Spacer()

            Menu {
                Button("Copy name") {
                    NSPasteboard.general.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
                    NSPasteboard.general.setString(device.name, forType: .string)
                }
                Button("Copy identifier") {
                    NSPasteboard.general.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
                    NSPasteboard.general.setString(device.id, forType: .string)
                }
                if let onPinned {
                    Divider()
                    Button(pinned ? "Unpin" : "Pin") {
                        onPinned(device, !pinned)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .opacity(0.8)
            }
            .buttonStyle(.plain)
        }
        .menuItemStyle()
        .onTapGesture {
            onSelected(device)
        }
    }
}
