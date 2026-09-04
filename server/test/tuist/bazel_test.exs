defmodule Tuist.BazelTest do
  use ExUnit.Case, async: true

  alias Tuist.Bazel

  test "redacts common credential forms" do
    message = """
    TUIST_TOKEN="ghp_realSecretValue"
    secret: 'abc123'
    Bearer eyJhbGciOiJIUzI1NiJ9.payload
    --token ghp_realSecretValue
    Authorization: Bearer another-secret
    token=unquoted-secret
    https://user:password@example.com/path
    """

    sanitized = Bazel.sanitize_log_message(message)

    refute sanitized =~ "ghp_realSecretValue"
    refute sanitized =~ "abc123"
    refute sanitized =~ "eyJhbGciOiJIUzI1NiJ9"
    refute sanitized =~ "another-secret"
    refute sanitized =~ "unquoted-secret"
    refute sanitized =~ "password@example.com"
    assert sanitized =~ "TUIST_TOKEN=<REDACTED>"
    assert sanitized =~ "--token <REDACTED>"
    assert sanitized =~ "https://<REDACTED>@example.com/path"
  end

  test "preserves ordinary tokens, tildes, and path-like words" do
    message = """
    unexpected token: identifier at line 4
    benchmark took ~100ms across a~b
    cleaning /tmpfiles/x and /homework/y
    """

    assert Bazel.sanitize_log_message(message) == message
  end

  test "redacts bounded local path prefixes" do
    message = "open /tmp/build.log and ~/project/test.log and /Users/developer/project/file"

    assert Bazel.sanitize_log_message(message) ==
             "open <LOCAL_PATH> and <LOCAL_PATH> and <LOCAL_PATH>"
  end
end
