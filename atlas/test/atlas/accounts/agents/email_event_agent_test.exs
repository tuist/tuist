defmodule Atlas.Accounts.Agents.EmailEventAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Agents.EmailEventAgent
  alias Atlas.LLMs

  test "returns :llm_not_configured when the LLM config is empty" do
    stub(LLMs, :config, fn -> nil end)

    email = %{
      subject: "Hello",
      message_id: nil,
      occurred_at: DateTime.utc_now(),
      from: [],
      to: [],
      cc: [],
      reply_to: [],
      participants: [],
      text_body: nil,
      envelope: %{}
    }

    assert {:error, :llm_not_configured} = EmailEventAgent.run(email)
  end

  test "documents service-provider account boundaries in the system prompt" do
    prompt = EmailEventAgent.system_prompt()

    assert prompt =~ "inbound customer emails"
    assert prompt =~ "Tuist acting as the service provider"
    assert prompt =~ "Tuist is the buyer"
    assert prompt =~ "not_account"
  end
end
