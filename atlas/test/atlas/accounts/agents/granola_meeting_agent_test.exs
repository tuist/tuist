defmodule Atlas.Accounts.Agents.GranolaMeetingAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Agents.GranolaMeetingAgent
  alias Atlas.Granola.Note
  alias Atlas.LLMs

  setup :verify_on_exit!

  test "returns :llm_not_configured when the LLM config is empty" do
    stub(LLMs, :config, fn -> nil end)

    note =
      Note.from_api(%{
        "id" => "not_test",
        "title" => "Renewal planning",
        "created_at" => "2026-05-07T13:00:00Z",
        "updated_at" => "2026-05-07T14:00:00Z",
        "attendees" => [%{"name" => "Maya Chen", "email" => "maya@acme.example"}],
        "summary_markdown" => "## Renewal"
      })

    assert {:error, :llm_not_configured} = GranolaMeetingAgent.run(note)
  end

  test "documents meeting markdown constraints in the system prompt" do
    prompt = GranolaMeetingAgent.system_prompt()

    assert prompt =~ "Granola customer meeting notes"
    assert prompt =~ "upsert_account"
    assert prompt =~ "summary_markdown"
    assert prompt =~ "Tuist acting as the service provider"
    assert prompt =~ "Tuist is the buyer"
    assert prompt =~ "Do not invent"
  end
end
