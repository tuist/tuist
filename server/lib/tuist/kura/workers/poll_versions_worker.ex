defmodule Tuist.Kura.Workers.PollVersionsWorker do
  @moduledoc """
  Polls the public GitHub Releases feed for new Kura tags
  (`kura@<semver>`) and writes them into the `kura_versions` table.

  Runs hourly via the Oban Cron plugin. Idempotent: existing rows are
  not touched, so the operator can safely fire the job manually as well.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.GitHub.Releases
  alias Tuist.GitHub.Retry
  alias Tuist.Kura

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    case fetch_releases() do
      {:ok, releases} ->
        releases
        |> Enum.flat_map(&extract_kura/1)
        |> Enum.each(fn {version, released_at} ->
          Kura.record_version(version, released_at)
        end)

        :ok

      {:error, reason} ->
        Logger.warning("[Kura.PollVersionsWorker] failed to fetch releases: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_releases do
    headers = [
      {"Accept", "application/vnd.github.v3+json"}
      | github_auth_headers()
    ]

    req_opts = [finch: Tuist.Finch, headers: headers] ++ Retry.retry_options()

    case Req.get(Releases.releases_url() <> "?per_page=100", req_opts) do
      {:ok, %Req.Response{status: 200, body: releases}} when is_list(releases) ->
        {:ok, releases}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:bad_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_auth_headers do
    case Tuist.Environment.github_token_update_package_releases() do
      nil -> []
      token -> [{"Authorization", "Bearer #{token}"}]
    end
  end

  # Releases are tagged like `kura@0.5.2`. Returns `{version, released_at}`
  # tuples for matching tags, dropping anything we can't parse.
  defp extract_kura(%{"tag_name" => "kura@" <> version, "published_at" => published_at}) do
    case DateTime.from_iso8601(published_at) do
      {:ok, dt, _offset} -> [{version, DateTime.truncate(dt, :second)}]
      _ -> []
    end
  end

  defp extract_kura(_), do: []
end
