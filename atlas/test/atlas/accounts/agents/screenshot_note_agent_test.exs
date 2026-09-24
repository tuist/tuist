defmodule Atlas.Accounts.Agents.ScreenshotNoteAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Agents.ScreenshotNoteAgent
  alias Atlas.LLMs

  test "returns :llm_not_configured when the LLM config is empty" do
    stub(LLMs, :config, fn -> nil end)
    base64 = Base.encode64(<<137, 80, 78, 71>>)

    assert {:error, :llm_not_configured} =
             ScreenshotNoteAgent.draft_note(base64, "image/png", %{name: "Acme"})
  end
end
