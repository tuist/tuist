import AutomaticModule
import DynamicModule
import Feature
import PromotedModule
import StaticModule
import SwiftUI

@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup { Text("Answer: \(Feature.answer)") }
    }
}

public enum HostState {
    public static var dynamic: DynamicState { DynamicState.shared }
    public static var explicitStatic: StaticState { StaticState.shared }
    public static var automatic: AutomaticState { AutomaticState.shared }
    public static var promotedAutomatic: PromotedState { PromotedState.shared }
}
