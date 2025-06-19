import ProjectResourcesFramework
import ResourcesFramework
import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        VStack {
            Text(ProjectResourcesFramework.ResourcesProvider.greeting())
            Text(ResourcesFramework.ResourcesProvider.greeting())
        }
        .padding()
    }
}
