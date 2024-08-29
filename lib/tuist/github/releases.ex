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
  use GenServer

  @releases_url "https://api.github.com/repos/tuist/tuist/releases"
  @refresh_interval :timer.hours(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{most_recent_cli_release: nil, most_recent_app_release: nil},
     {:continue, :fetch_release}}
  end

  def releases_url() do
    @releases_url
  end

  def get_latest_cli_release(pid \\ nil) do
    pid = pid || Process.whereis(__MODULE__)
    if is_nil(pid), do: nil, else: GenServer.call(pid, :get_cli_release)
  end

  def get_latest_app_release(pid \\ nil) do
    pid = pid || Process.whereis(__MODULE__)
    if is_nil(pid), do: nil, else: GenServer.call(pid, :get_app_release)
  end

  def handle_continue(:fetch_release, state) do
    new_state = %{
      state
      | most_recent_cli_release: fetch_latest_cli_release(),
        most_recent_app_release: fetch_latest_app_release()
    }

    schedule_refresh()
    {:noreply, new_state}
  end

  def handle_info(:refresh, state) do
    new_state = %{
      state
      | most_recent_cli_release: fetch_latest_cli_release(),
        most_recent_app_release: fetch_latest_app_release()
    }

    schedule_refresh()
    {:noreply, new_state}
  end

  def handle_call(:get_cli_release, _from, state) do
    {:reply, Map.get(state, :most_recent_cli_release, nil), state}
  end

  def handle_call(:get_app_release, _from, state) do
    {:reply, Map.get(state, :most_recent_app_release, nil), state}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  def fetch_latest_app_release do
    fetch_release(&String.contains?(&1, "app@"))
  end

  defp fetch_latest_cli_release do
    fetch_release(&(not String.contains?(&1, "@")))
  end

  defp fetch_release(filter) do
    case Req.get(releases_url()) do
      {:ok, %Req.Response{status: 200, body: releases}} ->
        release =
          releases
          |> Enum.find(&(Map.get(&1, "name") |> filter.()))

        if is_nil(release) do
          nil
        else
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

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        nil

      {:error, _reason} ->
        nil
    end
  end
end
