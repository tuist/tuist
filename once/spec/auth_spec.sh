#shellcheck shell=bash

Describe 'once auth'
  BeforeEach 'setup_workspace'
  AfterEach 'cleanup_workspace'

  It 'prints auth help and lists login and logout'
    When call "$ONCE_BIN" auth --help
    The status should be success
    The stdout should include 'login'
    The stdout should include 'logout'
  End

  It 'prints login help with provider and no-browser options'
    When call "$ONCE_BIN" auth login --help
    The status should be success
    The stdout should include '--provider'
    The stdout should include '--no-browser'
  End

  It 'prints logout help with the provider option'
    When call "$ONCE_BIN" auth logout --help
    The status should be success
    The stdout should include '--provider'
  End

  It 'lists the auth command surface'
    When call "$ONCE_BIN" auth --list
    The status should be success
    The stdout should include 'auth'
    The stdout should include 'login'
    The stdout should include 'logout'
    The stdout should include '--provider'
  End

  It 'rejects login when the workspace provider is local'
    cat > "$WORKSPACE/once.toml" <<'EOF'
[cache_provider]
kind = "local"
EOF

    When call once auth login --provider workspace
    The status should be failure
    The stderr should include 'does not support authentication'
  End

  It 'errors when an auth provider is unknown'
    When call once auth logout --provider missing
    The status should be failure
    The stderr should include 'auth provider `missing` was not found'
  End

  It 'logs out of the built-in Tuist provider without a stored session'
    When call once auth logout --provider tuist
    The status should be success
    The stdout should include 'no stored session for'
    The stdout should include 'tuist'
  End

  It 'resolves a named user infrastructure for auth logout'
    mkdir -p "$XDG_CONFIG_HOME/once"
    cat > "$XDG_CONFIG_HOME/once/config.toml" <<'EOF'
[infrastructures.acme]
kind = "tuist"
url = "https://tuist.dev"
account = "acme"
EOF

    When call once auth logout --provider acme
    The status should be success
    The stdout should include 'no stored session for'
    The stdout should include 'acme'
  End

  It 'resolves workspace auth through user infrastructure binding'
    mkdir -p "$XDG_CONFIG_HOME/once"
    cat > "$WORKSPACE/once.toml" <<'EOF'
[infrastructure.cache]
name = "acme"
account = "acme"
EOF
    cat > "$XDG_CONFIG_HOME/once/config.toml" <<'EOF'
[infrastructures.acme]
kind = "tuist"
url = "https://tuist.dev"
EOF

    When call once auth logout --provider workspace
    The status should be success
    The stdout should include 'no stored session for'
    The stdout should include 'acme'
  End
End
