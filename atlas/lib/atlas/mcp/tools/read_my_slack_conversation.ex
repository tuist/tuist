defmodule Atlas.MCP.Tools.ReadMySlackConversation do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "read_my_slack_conversation",
    schema: %{
      "type" => "object",
      "properties" => %{
        "channel_id" => %{"type" => "string", "minLength" => 1, "description" => "Channel or DM id, such as C0123ABCD."},
        "thread_timestamp" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Read this thread's replies (parent first) instead of the channel's history."
        },
        "permalink" => %{
          "type" => "string",
          "minLength" => 1,
          "description" =>
            "A Slack message link. Reads the thread the message is in, or just the message when it has no replies."
        },
        "oldest" => %{"type" => "string", "description" => "Only messages after this timestamp."},
        "latest" => %{"type" => "string", "description" => "Only messages before this timestamp."},
        "cursor" => %{"type" => "string", "description" => "next_cursor from the previous page."},
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 200, "description" => "Defaults to 50."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["channel_id", "thread_timestamp", "messages", "next_cursor"],
      "properties" => %{
        "channel_id" => %{"type" => "string"},
        "thread_timestamp" => %{"type" => ["string", "null"]},
        "next_cursor" => %{"type" => ["string", "null"]},
        "messages" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["text", "user", "timestamp", "thread_timestamp", "reply_count", "files"],
            "properties" => %{
              "text" => %{"type" => "string"},
              "user" => %{"type" => ["string", "null"]},
              "timestamp" => %{"type" => ["string", "null"]},
              "thread_timestamp" => %{"type" => ["string", "null"]},
              "reply_count" => %{"type" => ["integer", "null"]},
              "files" => %{"type" => "array", "items" => Atlas.Connections.Slack.file_schema()}
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
    "Read a Slack channel's history (newest first) or a thread's replies (parent first) through the caller's personal " <>
      "Slack connection (not the Atlas bot), including private channels, DMs and Slack Connect channels they belong to. " <>
      "Pass channel_id (and thread_timestamp for a thread) or a message permalink. Messages list their files; fetch one " <>
      "with download_my_slack_file. Users are Slack user ids."
  end

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Slack tools"),
         {:ok, channel, thread} <- target(args),
         {:ok, result} <-
           Slack.history(Tool.current_user(conn), channel,
             thread_timestamp: thread,
             limit: args["limit"],
             cursor: args["cursor"],
             oldest: args["oldest"],
             latest: args["latest"]
           ) do
      {:ok, result}
    else
      {:error, :shared_identity} -> {:error, "Personal Slack reads are unavailable to shared Slack identities."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, slack_error(reason)}
    end
  end

  defp target(%{"permalink" => permalink}) do
    case Slack.parse_permalink(permalink) do
      {:ok, channel, thread} -> {:ok, channel, thread}
      {:error, :invalid_permalink} -> {:error, "permalink must be a Slack message link (…/archives/<channel>/p<ts>)."}
    end
  end

  defp target(%{"channel_id" => channel} = args), do: {:ok, channel, args["thread_timestamp"]}
  defp target(_args), do: {:error, "channel_id or permalink is required."}

  @doc false
  def slack_error(:insufficient_scope) do
    "Your Slack connection does not include history and file access yet. Reconnect Slack at " <>
      AtlasWeb.Endpoint.url() <> "/settings/connections to grant it."
  end

  def slack_error(reason), do: ManageAccountConnections.connection_error("Slack", reason)
end
