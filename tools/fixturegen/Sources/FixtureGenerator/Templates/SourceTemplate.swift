import Foundation

class SourceTemplate {
    private let template = """
    import Foundation

    public class {FrameworkName}SomeClass{Number} {
       public init() {

       }

       public func hello() {

       }
    }

    """

    func generate(frameworkName: String, number: Int) -> String {
        template
            .replacingOccurrences(of: "{FrameworkName}", with: frameworkName)
            .replacingOccurrences(of: "{Number}", with: "\(number)")
    }
}
