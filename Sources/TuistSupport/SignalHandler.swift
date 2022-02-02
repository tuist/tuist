import Foundation

public typealias SigActionHandler = @convention(c) (Int32) -> Void

/// Signal handling
public protocol SignalHandling {
    /// Traps SIGINT or SIGABRT signals, and invokes the closure when received
    func trap(_ action: @escaping SigActionHandler)
}

/// Signal handler
public struct SignalHandler: SignalHandling {
    public init() {}

    public func trap(_ action: @escaping SigActionHandler) {
        trap(signal: SIGINT, action: action)
        trap(signal: SIGABRT, action: action)
    }

    private func trap(signal: Int32, action: @escaping SigActionHandler) {
        var signalAction = sigaction(__sigaction_u: unsafeBitCast(action, to: __sigaction_u.self), sa_mask: 0, sa_flags: 0)
        _ = withUnsafePointer(to: &signalAction) { actionPointer in
            sigaction(signal, actionPointer, nil)
        }
    }
}
