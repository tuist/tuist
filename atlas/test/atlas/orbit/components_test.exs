defmodule Atlas.Orbit.ComponentsTest do
  use ExUnit.Case, async: true

  alias Atlas.Orbit.Components
  alias Atlas.Orbit.Message

  test "server authors bounded data-only cards from the durable redacted rendering" do
    message = %Message{
      kind: "tool",
      tool_status: "succeeded",
      tool_name: "list_accounts",
      tool_output: JSON.encode!(%{"accounts" => [%{"name" => "Northstar", "status" => "active"}]})
    }

    assert %{
             type: "result_table",
             version: 1,
             data: %{title: "list_accounts", columns: ["name", "status"], rows: [["Northstar", "active"]]},
             actions: [%{id: "show_evidence", label: "View source"}],
             fallback: fallback
           } = Components.for_message(message)

    assert fallback == message.tool_output
    assert Components.for_message(%{message | tool_status: "running"}) == nil
    assert Components.for_message(%{message | tool_status: "failed"}) == nil
    assert Components.for_message(%{message | kind: "human"}) == nil
    assert Components.for_message(%{message | tool_output: "plain text"}) == nil
    assert Components.for_message(%{message | tool_output: "{truncated…"}) == nil
    assert Components.for_message(%{message | tool_output: "{}"}) == nil
  end

  test "cards never bypass redaction or inspect encrypted model results" do
    message = %Message{
      kind: "tool",
      tool_status: "succeeded",
      tool_name: "get_account",
      tool_output: JSON.encode!(%{"name" => "Northstar", "token" => "secret-value"}),
      tool_result: "encrypted model context must never reach this renderer"
    }

    encoded = message |> Components.for_message() |> JSON.encode!()
    assert encoded =~ "[redacted]"
    refute encoded =~ "secret-value"
    refute encoded =~ "encrypted model context"
  end

  test "bounds rows, columns and cells without depending on a particular organization's tools" do
    rows = for _ <- 1..8, do: %{"a" => String.duplicate("x", 200), "b" => 1, "c" => true, "d" => nil}
    message = %Message{kind: "tool", tool_status: "succeeded", tool_output: JSON.encode!(rows)}
    card = Components.for_message(message)
    assert card.data.columns == ["a", "b", "c"]
    assert length(card.data.rows) == 5
    assert String.length(hd(hd(card.data.rows))) == 160
    assert length(Enum.at(card.data.rows, 0)) == 3
    assert Components.for_message(%{message | tool_output: String.duplicate("x", 16_001)}) == nil
  end
end
