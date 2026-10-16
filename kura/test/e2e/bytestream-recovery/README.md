# Bazel ByteStream upload recovery

This fixture uses the actual `ByteStreamUploader`, `RemoteRetrier`, and gRPC transport bundled in the Bazel 9.1.1 binary pinned by `kura/mise.toml`. It compiles a small Java entry point against `A-server.jar`; it does not model Bazel's retry decisions. Update the fixture when the pinned Bazel version or these internal APIs change.

A local gRPC proxy forwards writes and status queries to real Kura. It forwards 6 MiB of the first write, beyond gRPC's transparent-replay buffer, and waits until gRPC has flushed them. Kura's fixed 4 MiB HTTP/2 stream window then means Kura has consumed roughly the last 2 MiB beyond it (gRPC reports readiness below a 32 KiB queue), so the interruption cancels a write that Kura is actually staging. The proxy then cancels the upstream call and returns `UNAVAILABLE`. The real uploader must query Kura, receive `UNIMPLEMENTED` for unavailable partial-upload status, and restart from zero. The second write must persist all 8 MiB. Read-back verifies the byte count and SHA-256. Both identity and zstd-compressed uploads run. The assertions require exactly two writes, one status query, and initial offsets `[0, 0]`, so transparent replay or a skipped failure cannot satisfy the test.

A second, fresh uploader then uploads the same blob again. Kura reads that write to completion without staging, decoding, or storing it, and answers exactly as for a full write. The fixture requires the real uploader to succeed and Kura's `already_present` write counter to increase by exactly one. Kura deliberately does not end the write early: answering before the client finishes forces an HTTP/2 stream reset, and enough of those on one connection trip the server's rapid-reset protection, which closes the whole connection.

The existing `clients` Shellspec suite invokes this fixture against its Dockerized Kura node. CI installs JDK 21 in that shard to compile the entry point and runs it using Bazel's bundled runtime. No new fixture Docker image or Maven dependencies are required.

To run against a local, auth-disabled Kura node:

```sh
mise exec java@21.0.2 -- bash test/e2e/bytestream-recovery/run.sh 127.0.0.1:4000
```

The script extracts an isolated Bazel installation and cleans its temporary files. To reuse an already-extracted matching installation, set `BAZEL_RECOVERY_INSTALL_BASE` to its directory.

This is an upload-recovery test, not an ingress connection-retirement test. It deliberately writes fixture artifacts to the target: use a disposable local or test node, never an unapproved production endpoint.
