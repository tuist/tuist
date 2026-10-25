import Path
import TuistProcess

struct RustupProbeRunner: CommandRunning {
    var activeToolchain = "stable-aarch64-apple-darwin"
    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let output = arguments.last == "active-toolchain"
                ? "\(activeToolchain) (overridden by '/workspace/rust-toolchain.toml')\n"
                : "/toolchains/stable/bin/cargo\n"
            continuation.yield(.standardOutput(Array(output.utf8)))
            continuation.finish()
        }
    }
}
