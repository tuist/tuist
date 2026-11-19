defmodule Condukt.Redactors.RegexTest do
  use ExUnit.Case, async: true

  alias Condukt.Redactors.Regex, as: RegexRedactor

  describe "redact/2 default patterns" do
    test "redacts email addresses" do
      assert RegexRedactor.redact("ping me at alice@example.com please", []) ==
               "ping me at [REDACTED:EMAIL] please"
    end

    test "redacts JWT tokens" do
      jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
      assert RegexRedactor.redact("token=" <> jwt, []) == "token=[REDACTED:JWT]"
    end

    test "redacts Anthropic API keys with the more specific label" do
      key = "sk-ant-api03-" <> String.duplicate("a", 40)
      assert RegexRedactor.redact("key=" <> key, []) == "key=[REDACTED:ANTHROPIC_KEY]"
    end

    test "redacts generic sk- API keys" do
      key = "sk-" <> String.duplicate("x", 40)
      assert RegexRedactor.redact("OPENAI=" <> key, []) == "OPENAI=[REDACTED:API_KEY]"
    end

    test "redacts GitHub tokens" do
      key = "ghp_" <> String.duplicate("a", 36)
      assert RegexRedactor.redact("auth: " <> key, []) == "auth: [REDACTED:GITHUB_TOKEN]"
    end

    test "redacts Google API keys" do
      key = "AIza" <> String.duplicate("z", 35)
      assert RegexRedactor.redact("k=" <> key, []) == "k=[REDACTED:GOOGLE_API_KEY]"
    end

    test "redacts AWS access key IDs" do
      assert RegexRedactor.redact("id=AKIAIOSFODNN7EXAMPLE here", []) ==
               "id=[REDACTED:AWS_ACCESS_KEY] here"
    end

    test "redacts Slack tokens" do
      assert RegexRedactor.redact("xoxb-12345-abcdefghij rest", []) ==
               "[REDACTED:SLACK_TOKEN] rest"
    end

    test "redacts PEM private key blocks across lines" do
      pem = """
      -----BEGIN RSA PRIVATE KEY-----
      MIIEpAIBAAKCAQEAxx
      morestuff
      -----END RSA PRIVATE KEY-----
      """

      result = RegexRedactor.redact("here: " <> pem, [])
      assert result =~ "[REDACTED:PRIVATE_KEY]"
      refute result =~ "MIIEpAIBAAKCAQEAxx"
    end

    test "leaves text without secrets untouched" do
      input = "the quick brown fox jumps over the lazy dog"
      assert RegexRedactor.redact(input, []) == input
    end

    test "redacts multiple secrets in one pass" do
      input = "alice@example.com sent ghp_" <> String.duplicate("a", 36)
      result = RegexRedactor.redact(input, [])
      assert result == "[REDACTED:EMAIL] sent [REDACTED:GITHUB_TOKEN]"
    end
  end

  describe "redact/2 with custom patterns" do
    test ":patterns replaces the defaults" do
      patterns = [{~r/internal-\d+/, "INTERNAL"}]

      assert RegexRedactor.redact("internal-42 alice@example.com", patterns: patterns) ==
               "[REDACTED:INTERNAL] alice@example.com"
    end

    test ":extra_patterns appends to the defaults" do
      assert RegexRedactor.redact(
               "cust_42 alice@example.com",
               extra_patterns: [{~r/cust_\d+/, "CUSTOMER"}]
             ) == "[REDACTED:CUSTOMER] [REDACTED:EMAIL]"
    end
  end

  describe "default_patterns/0" do
    test "returns the built-in pattern list" do
      patterns = RegexRedactor.default_patterns()
      assert is_list(patterns)
      refute Enum.empty?(patterns)
      assert Enum.all?(patterns, fn {regex, label} -> is_struct(regex, Regex) and is_binary(label) end)
    end
  end
end
