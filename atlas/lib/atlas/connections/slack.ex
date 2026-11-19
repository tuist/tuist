defmodule Atlas.Connections.Slack do
  @moduledoc """
  On-demand Slack message search through the caller's own personal Slack user
  token (`search:read`). This is separate from Atlas's workspace bot: results
  are limited to what the connected person can see in Slack.
  """

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Users.User

  @search "https://slack.com/api/search.messages"
  @max_results 50

  def search(%User{} = user, query, limit \\ 20) when is_binary(query) do
    limit = limit |> max(1) |> min(@max_results)

    with {:ok, token} <- Connections.access_token(user, "slack", ["search:read"]),
         {:ok, %{"messages" => %{"matches" => matches}}} when is_list(matches) <-
           request(token, query: query, count: limit, sort: "timestamp", sort_dir: "desc") do
      messages = Enum.map(matches, &message/1)
      audit(user, %{"count" => length(messages)})
      {:ok, messages}
    else
      {:ok, _} -> {:error, :invalid_response}
      {:error, _} = error -> error
    end
  end

  defp message(match) do
    channel = match["channel"] || %{}

    %{
      text: match["text"] || "",
      user: match["username"] || match["user"],
      channel_id: channel["id"],
      channel_name: channel["name"],
      timestamp: match["ts"],
      thread_timestamp: match["thread_ts"],
      permalink: match["permalink"]
    }
  end

  defp request(token, params) do
    case Req.request(
           method: :get,
           url: @search,
           auth: {:bearer, token},
           params: params,
           retry: false,
           redirect: false,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %{status: 200, body: %{"error" => "ratelimited"}}} ->
        {:error, :rate_limited}

      {:ok, %{status: 200, body: %{"error" => error}}}
      when error in ~w(invalid_auth token_revoked token_expired missing_scope account_inactive not_authed) ->
        {:error, :needs_authorization}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      _ ->
        {:error, :provider_unavailable}
    end
  end

  # Never record the query or message text.
  defp audit(user, metadata) do
    Audit.record(
      "connection.slack_searched",
      %{
        target_type: "user_connection",
        target_label: "slack",
        metadata: Map.merge(%{"provider" => "slack", "dashboard_path" => "/settings/connections"}, metadata)
      },
      actor: user
    )
  end
end
