defmodule Atlas.MCP.Tools.SyncMySocialPosts do
  @moduledoc """
  Runs the social post sync now for the caller's own X connection, instead of
  waiting for the daily job.
  """

  use Atlas.MCP.Tool,
    name: "sync_my_social_posts",
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "required" => ["posts"],
      "properties" => %{"posts" => %{"type" => "integer"}}
    }

  alias Atlas.GTM.SocialPosts
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Read the posts and metrics of the X account you connected in Atlas now, instead of waiting for the daily sync, and return how many posts were stored. Each run is billed by X per post read."

  def execute(conn, _args) do
    with :ok <- Tool.authorize_authenticated(conn, "Social post sync") do
      case SocialPosts.sync_x(Tool.current_user(conn), "mcp") do
        {:ok, count} -> {:ok, %{posts: count}}
        {:error, reason} -> {:error, "X sync failed: #{inspect(reason)}"}
      end
    end
  end
end
