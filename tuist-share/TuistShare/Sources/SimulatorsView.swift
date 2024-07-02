import SwiftUI
import TuistCore
import TuistServer
import TuistSupport
import Path

struct SimulatorView: View {
    @State var simulators: [SimulatorDeviceAndRuntime] = []
    @State var selectedSimulator: SimulatorDeviceAndRuntime?
    @EnvironmentObject private var appDelegate: AppDelegate
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(simulators) { simulator in
                    SimulatorRow(simulator: simulator, selected: simulator.device.udid == selectedSimulator?.device.udid) {
                        selectedSimulator = $0
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 5))
        .task {
            simulators = (try? await SimulatorController().devicesAndRuntimes().sorted(by: { if $0.device.name == $1.device.name { return $0.runtime.name < $1.runtime.name } else { return $0.device.name < $1.device.name } }).filter { $0.device.name.contains("iPhone") }) ?? []
            selectedSimulator = simulators.first(where: { !$0.device.isShutdown })
            
            
        }
        .onChange(of: appDelegate.url, initial: false) {
            guard 
                let url = appDelegate.url,
                let selectedSimulator
            else { return }
            Task {
                let downloadURL = try! await DownloadBuildService().downloadBuild(
                    "B6A87802-F741-4D47-A165-779F18552663",
                    serverURL: URL(string: "http://localhost:8080")!
                )
                let request = URLRequest(url: URL(string: downloadURL)!)
                do {
                    let (localURL, response) = try await URLSession.sharedCloud.download(for: request)
                    let appPath = try FileUnarchiver(path: try! AbsolutePath(validating: localURL.path)).unzip()
                    // TODO: App name should not be hardcoded
                        .appending(component: "App.app")
                    // TODO: Bundle ID needs to be passed from the server
                    try SimulatorController().installApp(at: appPath, device: selectedSimulator.device)
                    try SimulatorController().launchApp(bundleId: "io.tuist.App", device: selectedSimulator.device, arguments: [])
                    print(localURL)
                } catch let error {
                    print(error)
                }
            }
        }
    }
}

struct SimulatorRow: View {
    let simulator: SimulatorDeviceAndRuntime
    let selected: Bool
    let onSelected: (SimulatorDeviceAndRuntime) -> Void
    
    @State private var highlighted = false
    
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(selected ? .blue : .gray.opacity(0.4))
                Image(systemName: "iphone")
                    .foregroundColor(selected ? .white : .black)
            }
            .frame(width: 25, height: 25)
            VStack(alignment: .leading) {
                Text(simulator.device.name)
                    .font(.title3)
                Text("\(simulator.runtime.name)")
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5))
        .background(highlighted ? .gray.opacity(0.2) : .clear)
        .onHover(perform: { hovering in
            highlighted = hovering
        })
        .onTapGesture {
            onSelected(simulator)
        }
        .cornerRadius(5.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
