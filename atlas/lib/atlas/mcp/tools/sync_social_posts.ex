defmodule Atlas.MCP.Tools.SyncSocialPosts do
  @moduledoc """
  Runs the social post sync now for the X accounts Atlas holds, instead of
  waiting for the daily job.

  X bills every post read, so the tool needs `gtm:write`, is unavailable to
  the shared Slack agent, and runs a few times an hour across everyone.
  """

  use Atlas.MCP.Tool,
    name: "sync_social_posts",
    schema: %{
      "type" => "object",
      "properties" => %{
        "account" => %{"type" => "string", "description" => "Only this account handle, such as @tuistdev."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["accounts"],
      "properties" => %{
        "accounts" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["account", "kind"],
            "properties" => %{
              "account" => %{"type" => "string"},
              "kind" => %{"type" => "string"},
              "posts" => %{"type" => "integer"},
              "error" => %{"type" => "string"}
            }
          }
        }
      }
    }

  alias Atlas.GTM.SocialAccounts
  alias Atlas.GTM.SocialPosts
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias Atlas.RateLimit

  @window_milliseconds :timer.hours(1)
  @limit 3

  @impl EMCP.Tool
  def description,
    do:
      "Read the posts and metrics of the X accounts and LinkedIn pages connected in Atlas (GTM → Social → Post performance) now, instead of waiting for the daily sync, and return how many posts were stored per account. Pass `account` to sync one handle or page name. Each run is billed by X per post read, so it runs at most #{@limit} times an hour. Requires gtm:write."

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_scope(conn, "gtm:write", "Social post sync"),
         {:ok, accounts} <- accounts(args["account"]),
         {:allow, _attempts} <- RateLimit.hit("x-social-sync", @window_milliseconds, @limit) do
      user = Tool.current_user(conn)
      {:ok, %{accounts: Enum.map(accounts, &sync(&1, user))}}
    else
      {:error, :shared_identity} -> {:error, "Syncing social posts is unavailable to shared Slack identities."}
      {:deny, _remaining} -> {:error, "X sync is rate limited to #{@limit} runs an hour; try again later."}
      {:error, _} = error -> error
    end
  end

  defp accounts(handle) do
    case Enum.filter(SocialAccounts.list(), &(is_nil(handle) or &1.handle == handle)) do
      [] when is_binary(handle) -> {:error, "No connected social account is #{handle}."}
      [] -> {:error, "No social accounts are connected. Connect one in GTM → Social → Post performance."}
      accounts -> {:ok, accounts}
    end
  end

  defp sync(account, user) do
    case SocialPosts.sync_account(account, actor: user, interface: "mcp") do
      {:ok, count} -> %{account: account.handle, kind: account.kind, posts: count}
      {:error, :needs_authorization} -> %{account: account.handle, kind: account.kind, error: "needs reconnecting"}
      {:error, reason} -> %{account: account.handle, kind: account.kind, error: inspect(reason)}
    end
  end
end
