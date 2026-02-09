import ArgumentParser
import Foundation

public protocol TrackableParsableCommand {
    var analyticsRequired: Bool { get }
}
