import Foundation
import Logging
import TuistLogging

public protocol UserInputReading {
    func readString(asking prompt: String) -> String
}

public struct UserInputReader: UserInputReading {
    private var reader: (Bool) -> String?

    public init(reader: @escaping (Bool) -> String? = readLine) {
        self.reader = reader
    }

    public func readString(asking prompt: String) -> String {
        while true {
            Logger.current.notice("\(prompt)")
            if let input = reader(true), !input.isEmpty {
                return input
            } else {
                Logger.current.notice("The value is empty. Please, enter a non-empty value.")
            }
        }
    }
}
