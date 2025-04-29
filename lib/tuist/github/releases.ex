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

  alias Tuist.KeyValueStore

  @releases_url "https://api.github.com/repos/tuist/tuist/releases"
  @ttl to_timeout(hour: 1)

  def releases_url do
    @releases_url
  end

  def get_latest_cli_release(opts \\ []) do
    case opts
         |> fetch_releases()
         |> Enum.find(fn release ->
           not String.contains?(release["name"], "@")
         end) do
      nil -> nil
      release -> map_release(release)
    end
  end

  def get_latest_app_release(opts \\ []) do
    opts
    |> fetch_releases()
    |> Enum.map(&map_release/1)
    |> Enum.find(fn release ->
      String.contains?(release.name, "app@") and
        Enum.find(release.assets, &String.ends_with?(&1.browser_download_url, "dmg"))
    end)
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
    case Req.get(releases_url(), finch: Tuist.Finch) do
      {:ok, %Req.Response{status: 200, body: releases}} ->
        releases

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        []

      {:error, _reason} ->
        []
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
end
