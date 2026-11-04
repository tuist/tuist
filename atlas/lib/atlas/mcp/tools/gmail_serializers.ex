defmodule Atlas.MCP.Tools.GmailSerializers do
  @moduledoc false

  @doc "A Gmail message summary, optionally with extra required properties."
  def message_schema(extra \\ %{}) do
    %{
      "type" => "object",
      "required" => ["id", "thread_id", "from", "to", "subject", "date", "snippet", "labels"] ++ Map.keys(extra),
      "properties" =>
        Map.merge(
          %{
            "id" => %{"type" => "string"},
            "thread_id" => %{"type" => ["string", "null"]},
            "from" => %{"type" => "string"},
            "to" => %{"type" => "string"},
            "subject" => %{"type" => "string"},
            "date" => %{"type" => "string"},
            "snippet" => %{"type" => "string"},
            "labels" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          extra
        ),
      "additionalProperties" => false
    }
  end
end
