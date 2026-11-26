defmodule Atlas.MCP.Tools.GetOutreachResults do
  @moduledoc "Reports outreach results per sender and channel."

  use Atlas.MCP.Tool,
    name: "get_outreach_results",
    schema: %{
      "type" => "object",
      "properties" => %{"days" => %{"type" => "integer", "minimum" => 1, "maximum" => 365}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["results"],
      "properties" => %{
        "results" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "sender" => %{"type" => "string"},
              "channel" => %{"type" => "string"},
              "sent" => %{"type" => "integer"},
              "replies" => %{"type" => "integer"},
              "positive_replies" => %{"type" => "integer"},
              "meetings" => %{"type" => "integer"},
              "reply_rate" => %{"type" => ["number", "null"]},
              "meeting_rate" => %{"type" => ["number", "null"]}
            }
          }
        }
      }
    }

  alias Atlas.Outreach.MessageAttempts

  @impl EMCP.Tool
  def description,
    do:
      "Messages sent in the last `days` days (default 90) per teammate who sent them and channel (LinkedIn or X), with replies, positive replies, booked meetings and their rates."

  def execute(_conn, args), do: {:ok, %{results: MessageAttempts.summary(days: args["days"] || 90)}}
end
