The fleet image build places Darwin arm64 sbx-macos and sbx-worker here before
compiling tart-kubelet. Run go generate in internal/macosandbox for local builds.
Binaries are embedded in the kubelet artifact and unpacked by content hash.
