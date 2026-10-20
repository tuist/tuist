defmodule Atlas.Accounts.Agents.OverviewSummaryAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Agents.OverviewSummaryAgent
  alias Atlas.LLMs

  test "returns :llm_not_configured when no LLM config is available" do
    stub(LLMs, :config, fn -> nil end)

    account = %{
      name: "Acme",
      segment: :customer,
      description: nil,
      current_value: nil,
      currency: nil,
      next_renewal_date: nil,
      primary_domain: "acme.example",
      events: []
    }

    assert {:error, :llm_not_configured} = OverviewSummaryAgent.summarize(account)
  end

  test "documents Markdown output in the system prompt" do
    prompt = OverviewSummaryAgent.system_prompt()

    assert prompt =~ "Markdown"
    assert prompt =~ "bullet list"
    assert prompt =~ "Do not invent facts"
  end
end
