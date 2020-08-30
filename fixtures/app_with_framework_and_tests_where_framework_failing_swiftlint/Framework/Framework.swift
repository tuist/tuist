import Foundation

public class FrameworkClass       {
    public init() {}
    
    func foo() {
        let bar: Int? = 2
        print(bar!) // trigger opt_in `force_unwrapping` rule
    }
    
    
    
    
    
    
    
}
