import ExtensionKit

@main
final class VendorExtension: NSObject, AppExtension {
    override init() {}
    
    var configuration: Config {
        return Config()
    }
}

struct Config: AppExtensionConfiguration {
    func accept(connection _: NSXPCConnection) -> Bool {
        true
    }
}
