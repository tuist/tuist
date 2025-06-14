import ArgumentParser
import Foundation

protocol TrackableParsableCommand {
    var analyticsRequired: Bool { get }
}
