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

  @releases_url "https://api.github.com/repos/tuist/tuist/releases"
  @cache_key "tuist_releases"
  @ttl :timer.hours(24)

  def releases_url() do
    @releases_url
  end

  def get_latest_cli_release(opts \\ []) do
    case fetch_releases(opts)
         |> Enum.find(fn release ->
           not (release["name"] |> String.contains?("@"))
         end) do
      nil -> nil
      release -> map_release(release)
    end
  end

  def get_latest_app_release(opts \\ []) do
    case fetch_releases(opts)
         |> Enum.find(fn release ->
           release["name"] |> String.contains?("app@")
         end) do
      nil -> nil
      release -> map_release(release)
    end
  end

  defp fetch_releases(opts) do
    cache = opts |> Keyword.get(:cache, :tuist)
    ttl = opts |> Keyword.get(:ttl, @ttl)

    case Cachex.fetch(cache, @cache_key, fn ->
           {:commit, req_releases(), ttl: ttl}
         end) do
      {:commit, releases, _} -> releases
      {:ok, releases} -> releases
    end
  end

  defp req_releases() do
    case Req.get(releases_url()) do
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
        release["assets"]
        |> Enum.map(
          &%{
            name: &1["name"],
            browser_download_url: &1["browser_download_url"]
          }
        )
    }
  end
end
