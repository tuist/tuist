// The Swift Programming Language
// https://docs.swift.org/swift-book

import Alamofire

enum MyPackage {
    static func myPackage() {
        _ = AF.download("http://www.tuist.io")
    }
}
