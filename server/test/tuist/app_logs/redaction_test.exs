defmodule Tuist.AppLogs.RedactionTest do
  use ExUnit.Case, async: true

  alias Tuist.AppLogs.Redaction

  test "redacts bearer tokens, token parameters, and JWTs" do
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl"

    assert Redaction.redact("Authorization: Bearer abc.def-123") == "Authorization: [redacted] [redacted]"
    assert Redaction.redact("refresh_token=secret&grant_type=refresh") == "refresh_token=[redacted]&grant_type=refresh"
    assert Redaction.redact(~s({"access_token": "secret"})) == ~s({"access_token": "[redacted]"})
    assert Redaction.redact("token #{jwt} stored") == "token [redacted] stored"
  end

  test "redacts Tuist account and project tokens" do
    token = "tuist_0190f5a2-7c1e-7b6a-9e0f-3d2c1b0a9f8e_a1b2c3d4e5f6a7b8c9d0e1f2"

    assert Redaction.redact("Using #{token} to upload") == "Using [redacted] to upload"
  end

  test "redacts URL query strings, which can carry signed URLs" do
    url = "https://storage.example.com/previews/app.zip?X-Amz-Signature=abc&X-Amz-Credential=def"

    assert Redaction.redact("Downloading #{url} now") ==
             "Downloading https://storage.example.com/previews/app.zip?[redacted] now"
  end

  test "redacts email addresses" do
    assert Redaction.redact("Signed in as someone@example.com") == "Signed in as [redacted]"
  end

  test "redacts the user name in home directory paths" do
    assert Redaction.redact("Reading /Users/jane/Library/Developer/app.zip") ==
             "Reading /Users/[redacted]/Library/Developer/app.zip"
  end

  test "keeps lines without sensitive values unchanged" do
    line = "Authentication state updated to logged out"

    assert Redaction.redact(line) == line
  end
end
