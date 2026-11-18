defmodule Atlas.MCP.Tools.SearchMySlack do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "search_my_slack",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Slack search syntax, for example `deploy in:#eng after:2026-10-01` or `from:@alice`."
        },
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 50, "description" => "Defaults to 20."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["messages"],
      "properties" => %{
        "messages" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["text", "user", "channel_id", "channel_name", "timestamp", "thread_timestamp", "permalink"],
            "properties" => %{
              "text" => %{"type" => "string"},
              "user" => %{"type" => ["string", "null"]},
              "channel_id" => %{"type" => ["string", "null"]},
              "channel_name" => %{"type" => ["string", "null"]},
              "timestamp" => %{"type" => ["string", "null"]},
              "thread_timestamp" => %{"type" => ["string", "null"]},
              "permalink" => %{"type" => ["string", "null"]}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    }

  alias Atlas.Connections.Slack
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections

  @impl EMCP.Tool
  def description do
    "Search Slack messages visible to the caller, newest first, through their personal Slack connection " <>
      "(not the Atlas bot). Includes private channels and DMs the caller belongs to."
  end

  def execute(conn, %{"query" => query} = args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Slack tools"),
         {:ok, messages} <- Slack.search(Tool.current_user(conn), query, Map.get(args, "limit", 20)) do
      {:ok, %{messages: messages}}
    else
      {:error, :shared_identity} -> {:error, "Personal Slack search is unavailable to shared Slack identities."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, ManageAccountConnections.connection_error("Slack", reason)}
    end
  end

  def execute(_conn, _args), do: {:error, "query is required."}
end
