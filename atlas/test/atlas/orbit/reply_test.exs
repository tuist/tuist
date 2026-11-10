defmodule Atlas.Orbit.ReplyTest do
  use ExUnit.Case, async: true

  alias Atlas.Orbit.Reply

  test "keeps the answer independent of optional follow-up metadata and accepts fenced responses" do
    for metadata <- [%{}, %{suggestions: nil}, %{suggestions: "invalid"}] do
      encoded = JSON.encode!(Map.put(metadata, :reply, "  **Found it.**  "))
      assert Reply.decode(encoded) == {"**Found it.**", []}
      assert Reply.decode("```json\n#{encoded}\n```") == {"**Found it.**", []}
    end

    for text <- ["A legacy **Markdown** reply.", "```json\n{\"example\": true}\n```", "{incomplete"] do
      assert Reply.decode(text) == {text, []}
    end
  end

  test "bounds, trims and deduplicates model follow-ups without changing the primary reply" do
    boundary = String.duplicate("🪐", 120)

    encoded =
      JSON.encode!(%{
        reply: "The release is ready.",
        suggestions: [
          nil,
          " ",
          " Show its tasks ",
          "Show its tasks",
          String.duplicate("x", 121),
          String.duplicate("🪐", 121),
          boundary,
          "Compare release risks",
          "One too many"
        ]
      })

    assert Reply.decode(encoded) == {"The release is ready.", ["Show its tasks", boundary, "Compare release risks"]}
  end
end
