#shellcheck shell=bash
# End-to-end specs for `once run`.

Describe 'once run'
  BeforeEach 'setup_workspace'
  AfterEach 'cleanup_workspace'

  It 'errors when the target id does not match any target'
    touch "$WORKSPACE/once.toml"
    When call once run nope
    The status should not equal 0
    The stderr should include 'no target matches'
  End

  It 'rejects script declarations in once.toml'
    cat > "$WORKSPACE/once.toml" <<'EOF'
[[script]]
name = "hello"
argv = ["/bin/sh", "-c", "printf hello"]
EOF
    When call once run hello
    The status should not equal 0
    The stderr should include 'unknown field `script`'
  End
End
