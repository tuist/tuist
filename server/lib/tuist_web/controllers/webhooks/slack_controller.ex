defmodule TuistWeb.Webhooks.SlackController do
  use TuistWeb, :controller

  alias Tuist.Builds
  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Slack.Unfurl

  require Logger

  def handle(conn, %{"event" => %{"type" => "link_shared"} = event} = params) do
    team_id = params["team_id"]

    case Slack.get_installation_by_team_id(team_id) do
      {:ok, installation} ->
        process_link_shared(installation, event)

      {:error, :not_found} ->
        Logger.warning("Slack link_shared event from unknown team_id=#{team_id}")
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  def handle(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp process_link_shared(installation, %{"channel" => channel, "message_ts" => ts, "links" => links}) do
    unfurls =
      Enum.reduce(links, %{}, fn %{"url" => url}, acc ->
        case build_unfurl_for_url(url) do
          {:ok, attachment} -> Map.put(acc, url, attachment)
          :skip -> acc
        end
      end)

    if map_size(unfurls) > 0 do
      case Client.unfurl(installation.access_token, channel, ts, unfurls) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to unfurl links: #{inspect(reason)}")
      end
    end
  end

  defp process_link_shared(_installation, _event), do: :ok

  defp build_unfurl_for_url(url) do
    case Unfurl.parse_url(url) do
      {:ok, {:build_run, %{build_run_id: build_run_id}}} ->
        case Builds.get_build(build_run_id) do
          nil ->
            :skip

          build ->
            build = Repo.preload(build, project: :account)
            {:ok, Unfurl.build_build_run_blocks(build, url)}
        end

      :error ->
        :skip
    end
  end
end
