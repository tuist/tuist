import ExtensionKit

@main
final class VendorExtension: NSObject, AppExtension {
    var configuration: Config {
        return Config()
    }
}

struct Config: AppExtensionConfiguration {
    func accept(connection _: NSXPCConnection) -> Bool {
        true
    }
}
