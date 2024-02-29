import Alamofire

enum MyPackage {
    static func myPackage() {
        _ = AF.download("http://www.tuist.io")
    }
}
