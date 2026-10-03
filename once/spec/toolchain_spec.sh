#shellcheck shell=bash
# End-to-end specs for `once toolchain inspect`.

Describe 'once toolchain inspect'
  BeforeEach 'setup_workspace'
  AfterEach 'cleanup_workspace'

  It 'prints a human-readable contract from mise.toml'
    cat > "$WORKSPACE/mise.toml" <<'EOF'
[tools]
rust = "1.86"
shellspec = "latest"

[env]
RUST_BACKTRACE = "1"
EOF
    When call once toolchain inspect
    The status should be success
    The stdout should include 'source: mise'
    The stdout should include 'config: mise.toml'
    The stdout should include 'lock: missing'
    The stdout should include 'fingerprint: blake3:'
    The stdout should include 'rust 1.86'
    The stdout should include 'shellspec latest'
    The stdout should include 'RUST_BACKTRACE = 1'
  End

  It 'emits a single JSON object under --format json'
    cat > "$WORKSPACE/mise.toml" <<'EOF'
[tools]
rust = "1.86"
EOF
    When call "$ONCE_BIN" --format json -C "$WORKSPACE" toolchain inspect
    The status should be success
    The stdout should include '"source":"mise"'
    The stdout should include '"config":"mise.toml"'
    The stdout should include '"tools":'
    The stdout should include '"name":"rust"'
    The stdout should include '"request":"1.86"'
    The stdout should include '"fingerprint":"blake3:'
  End

  It 'includes lockfile data when mise.lock exists'
    cat > "$WORKSPACE/mise.toml" <<'EOF'
[tools]
rust = "1.86"
EOF
    cat > "$WORKSPACE/mise.lock" <<'EOF'
[[tools.rust]]
version = "1.86.0"
backend = "core:rust"
EOF
    When call "$ONCE_BIN" --format json -C "$WORKSPACE" toolchain inspect
    The status should be success
    The stdout should include '"lock":"mise.lock"'
    The stdout should include '"locked":'
    The stdout should include '"version":"1.86.0"'
    The stdout should include '"backend":"core:rust"'
  End

  It 'uses requested platform data when --platform is passed'
    cat > "$WORKSPACE/mise.toml" <<'EOF'
[tools]
rust = "1.86"
EOF
    cat > "$WORKSPACE/mise.lock" <<'EOF'
[[tools.rust]]
version = "1.86.0"
backend = "core:rust"

[tools.rust.platforms.linux-x64]
checksum = "sha256:linux"
url = "https://example.test/rust-linux.tar.gz"
EOF
    When call "$ONCE_BIN" --format json -C "$WORKSPACE" toolchain inspect --platform linux-x64
    The status should be success
    The stdout should include '"mise":"linux-x64"'
    The stdout should include '"key":"linux-x64"'
    The stdout should include '"checksum":"sha256:linux"'
  End

  It 'fails clearly when mise.toml is missing'
    When call once toolchain inspect
    The status should not equal 0
    The stderr should include 'no mise.toml found'
  End
End
