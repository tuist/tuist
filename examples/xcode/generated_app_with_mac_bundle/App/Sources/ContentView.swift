import ProjectResourcesFramework
import ResourcesFramework
import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text(ProjectResourcesFramework.ResourcesProvider.greeting())
            Text(ResourcesFramework.ResourcesProvider.greeting())
            Text("Brand color loaded: \(ProjectResourcesFramework.ResourcesProvider.brandColorIsLoaded ? "YES" : "NO")")
            Rectangle()
                .fill(ProjectResourcesFramework.ResourcesProvider.brandColor)
                .frame(width: 120, height: 60)
        }
        .padding()
    }
}
