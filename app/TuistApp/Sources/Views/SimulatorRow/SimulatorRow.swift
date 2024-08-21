import class AppKit.NSPasteboard
import Foundation
import SwiftUI
import TuistCore
import TuistSupport

struct SimulatorRow: View, ErrorViewHandling {
    let simulator: SimulatorDeviceAndRuntime
    let selected: Bool
    let pinned: Bool
    let onSelected: (SimulatorDeviceAndRuntime) -> Void
    let onPinned: (SimulatorDeviceAndRuntime, Bool) -> Void

    @State var viewModel = SimulatorRowViewModel()
    @EnvironmentObject var errorHandling: ErrorHandling
    @State private var highlighted = false

    private func deviceImage() -> some View {
        switch simulator.runtime.platform {
        case .iOS, .none:
            if simulator.device.name.contains("iPad") {
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
                    .foregroundColor(selected ? TuistAsset.Assets.light.swiftUIColor : TuistAsset.Assets.dark.swiftUIColor)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading) {
                Text(simulator.device.name)
                    .font(.title3)
                Text("\(simulator.runtime.name)")
            }
            Spacer()

            Menu {
                Button(
                    "Launch"
                ) {
                    tryWithErrorHandler {
                        try await viewModel.launchSimulator(simulator)
                    }
                }
                Divider()
                Button("Copy name") {
                    NSPasteboard.general.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
                    NSPasteboard.general.setString(simulator.device.name, forType: .string)
                }
                Button("Copy identifier") {
                    NSPasteboard.general.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
                    NSPasteboard.general.setString(simulator.device.udid, forType: .string)
                }
                Divider()
                Button(pinned ? "Unpin" : "Pin") {
                    onPinned(simulator, !pinned)
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
            onSelected(simulator)
        }
    }
}
