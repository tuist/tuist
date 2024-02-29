import Alamofire

public func start() {
    // Use Alamofire to make sure it links fine
    _ = AF.download("http://www.tuist.io")
}
