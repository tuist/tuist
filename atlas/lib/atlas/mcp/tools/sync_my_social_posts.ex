defmodule Atlas.MCP.Tools.SyncMySocialPosts do
  @moduledoc """
  Runs the social post sync now for the caller's own X connection, instead of
  waiting for the daily job.

  X bills every post read, so the tool is for a person over their own
  connection only (never the shared Slack agent) and runs a few times an hour
  per person at most.
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
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias Atlas.RateLimit

  @window_milliseconds :timer.hours(1)
  @limit 3

  @impl EMCP.Tool
  def description,
    do:
      "Read the posts and metrics of the X account you connected in Atlas now, instead of waiting for the daily sync, and return how many posts were stored. Each run is billed by X per post read, so it runs at most #{@limit} times an hour."

  def execute(conn, _args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Social post sync"),
         user = Tool.current_user(conn),
         {:allow, _attempts} <- RateLimit.hit("x-social-sync:#{user.id}", @window_milliseconds, @limit) do
      case SocialPosts.sync_x(user, "mcp") do
        {:ok, count} -> {:ok, %{posts: count}}
        {:error, reason} -> {:error, "X sync failed: #{inspect(reason)}"}
      end
    else
      {:error, :shared_identity} -> {:error, "Syncing a person's X posts is unavailable to shared Slack identities."}
      {:deny, _remaining} -> {:error, "X sync is rate limited to #{@limit} runs an hour; try again later."}
      {:error, _} = error -> error
    end
  end
end
