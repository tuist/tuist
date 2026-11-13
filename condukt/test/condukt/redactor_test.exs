defmodule Condukt.RedactorTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.Redactor

  defmodule UpcaseRedactor do
    @behaviour Condukt.Redactor

    @impl true
    def redact(text, opts) do
      prefix = Keyword.get(opts, :prefix, "")
      prefix <> String.upcase(text)
    end
  end

  describe "apply/2" do
    test "returns text unchanged when spec is nil" do
      assert Redactor.apply(nil, "hello") == "hello"
    end

    test "dispatches to a bare module with empty opts" do
      assert Redactor.apply(UpcaseRedactor, "hi") == "HI"
    end

    test "passes opts when spec is a {module, opts} tuple" do
      assert Redactor.apply({UpcaseRedactor, prefix: ">> "}, "hi") == ">> HI"
    end

    test "applies a list of redactors in order" do
      secret_redactor = Condukt.Secrets.redactor(%Condukt.Secrets{env: [{"TOKEN", "secret-token"}]})

      assert Redactor.apply([secret_redactor, UpcaseRedactor], "value secret-token") ==
               "VALUE [REDACTED:TOKEN]"
    end
  end

  describe "redact_messages/2" do
    test "returns messages unchanged when spec is nil" do
      messages = [Message.user("secret"), Message.assistant("reply")]
      assert Redactor.redact_messages(nil, messages) == messages
    end

    test "redacts user message content" do
      [redacted] = Redactor.redact_messages(UpcaseRedactor, [Message.user("hi")])
      assert redacted.content == "HI"
      assert redacted.role == :user
    end

    test "leaves assistant messages untouched" do
      msg = Message.assistant("from llm")
      assert [^msg] = Redactor.redact_messages(UpcaseRedactor, [msg])
    end

    test "redacts tool_result string content" do
      msg = Message.tool_result("call-1", "tool said hi")
      [redacted] = Redactor.redact_messages(UpcaseRedactor, [msg])
      assert redacted.content == "TOOL SAID HI"
      assert redacted.tool_call_id == "call-1"
    end

    test "JSON-encodes non-binary tool_result content before redacting" do
      msg = Message.tool_result("call-2", %{"value" => "secret"})
      [redacted] = Redactor.redact_messages(UpcaseRedactor, [msg])
      assert redacted.content == ~s({"VALUE":"SECRET"})
    end

    test "leaves assistant block lists untouched" do
      msg = Message.assistant([{:text, "hello"}, {:tool_call, "id", "name", %{}}])
      assert [^msg] = Redactor.redact_messages(UpcaseRedactor, [msg])
    end
  end
end
