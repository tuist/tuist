defmodule Tuist.GitHub.Releases do
  @moduledoc ~S"""
  This module provides functionality to fetch and manage information about the latest CLI release
  of Tuist from GitHub. It uses a GenServer to periodically fetch and cache the release data,
  ensuring that the information is up-to-date while minimizing API calls.

  The module offers the following main features:
  - Fetches the latest CLI and App release information from the Tuist GitHub repository
  - Caches the release data and refreshes it periodically
  - Provides a function to retrieve the latest CLI release information

  The GenServer runs with a 1-hour refresh interval, balancing between having recent data
  and avoiding excessive API requests to GitHub.
  """

  alias Tuist.GitHub.Retry
  alias Tuist.KeyValueStore

  require Logger

  @releases_url "https://api.github.com/repos/tuist/tuist/releases"
  @ttl to_timeout(hour: 1)

  def releases_url do
    @releases_url
  end

  def get_latest_cli_release(opts \\ []) do
    if Tuist.Environment.dev?() do
      nil
    else
      case opts
           |> fetch_releases()
           |> Enum.find(fn release ->
             not String.contains?(release["name"], "@")
           end) do
        nil -> nil
        release -> map_release(release)
      end
    end
  end

  def get_latest_app_release(opts \\ []) do
    if Tuist.Environment.dev?() do
      nil
    else
      KeyValueStore.get_or_update(
        [__MODULE__, "github_latest_app_release"],
        [ttl: Keyword.get(opts, :ttl, @ttl)],
        fn ->
          fetch_latest_app_release()
        end
      )
    end
  end

  defp fetch_releases(opts) do
    KeyValueStore.get_or_update(
      [__MODULE__, "github_releases"],
      [ttl: Keyword.get(opts, :ttl, @ttl)],
      fn ->
        req_releases()
      end
    )
  end

  defp req_releases do
    headers = github_auth_headers()
    req_opts = [finch: Tuist.Finch, headers: headers] ++ Retry.retry_options()

    case Req.get(releases_url(), req_opts) do
      {:ok, %Req.Response{status: 200, body: releases}} ->
        releases

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        []

      {:error, _reason} ->
        []
    end
  end

  defp github_auth_headers do
    case Tuist.Environment.github_token_update_package_releases() do
      nil ->
        []

      token ->
        [
          {"Accept", "application/vnd.github.v3+json"},
          {"Authorization", "Bearer #{token}"}
        ]
    end
  end

  defp map_release(release) do
    %{
      name: release["name"],
      published_at: Timex.parse!(release["published_at"], "{ISO:Extended}"),
      html_url: release["html_url"],
      assets:
        Enum.map(
          release["assets"],
          &%{name: &1["name"], browser_download_url: &1["browser_download_url"]}
        )
    }
  end

  defp fetch_latest_app_release(opts \\ []) do
    url = Keyword.get(opts, :url, releases_url())
    headers = github_auth_headers()
    req_opts = [finch: Tuist.Finch, headers: headers] ++ Retry.retry_options()

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: releases, headers: headers}} ->
        next_url = extract_next_url(headers)

        releases = Enum.map(releases, &map_release/1)

        case find_app_release_from_releases(releases) do
          nil when next_url != nil ->
            fetch_latest_app_release(url: next_url)

          result ->
            result
        end

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        Logger.error("Failed to fetch GitHub releases, status: #{status}")
        nil

      {:error, reason} ->
        Logger.error("Failed to fetch GitHub releases, reason: #{inspect(reason)}")
        nil
    end
  end

  defp find_app_release_from_releases(releases) do
    Enum.find(releases, fn release ->
      String.contains?(release.name, "app@") and
        Enum.find(release.assets, &String.ends_with?(&1.browser_download_url, "dmg"))
    end)
  end

  defp extract_next_url(headers) do
    Enum.find_value(headers, fn
      {"link", [link_header | _]} ->
        parse_link_header(link_header)

      _ ->
        nil
    end)
  end

  defp parse_link_header(link_header) do
    # Parse GitHub's Link header format: <url>; rel="next"
    case Regex.run(~r/<([^>]+)>;\s*rel="next"/, link_header) do
      [_, next_url] -> next_url
      _ -> nil
    end
  end
end
