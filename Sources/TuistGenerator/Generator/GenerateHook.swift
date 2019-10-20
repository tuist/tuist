import Basic

public protocol GenerateHook {
    
    var owner: Generating { get }
    
    func pre(path: AbsolutePath) throws
    func post(path: AbsolutePath) throws
    
}
