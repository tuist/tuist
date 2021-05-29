import Foundation

public class FrameworkClass       {
    public init() {}
    
    func foo() {
        let bar: Int? = 2
        print(bar!) // triggers opt_in `force_unwrapping` rule


    
    }
    
    func bar() {
        NSNumber() ↓as! Int //  triggers `force_cast` rule
    }
    
    
    
    
    
}
