import Alamofire

public struct MyStruct {
    public init() {
        _ = AF.download("http://www.tuist.io")
    }
}
