defmodule Tuist.GitHub.Releases do
  @moduledoc ~S"""
  This module provides functionality to fetch and manage information about the latest CLI release
  of Tuist from GitHub. It uses a GenServer to periodically fetch and cache the release data,
  ensuring that the information is up-to-date while minimizing API calls.

  The module offers the following main features:
  - Fetches the latest CLI release information from the Tuist GitHub repository
  - Caches the release data and refreshes it periodically
  - Provides a function to retrieve the latest CLI release information

  The GenServer runs with a 1-hour refresh interval, balancing between having recent data
  and avoiding excessive API requests to GitHub.
  """
  use GenServer

  @latest_cli_release_url "https://api.github.com/repos/tuist/tuist/releases/latest"
  @refresh_interval :timer.hours(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{most_recent_cli_release: nil}, {:continue, :fetch_release}}
  end

  def latest_cli_release_url() do
    @latest_cli_release_url
  end

  def foo() do
    __MODULE__
  end

  def get_latest_cli_release(pid \\ nil) do
    GenServer.call(pid || __MODULE__, :get_release)
  end

  def handle_continue(:fetch_release, state) do
    new_state = %{state | most_recent_cli_release: fetch_release()}
    schedule_refresh()
    {:noreply, new_state}
  end

  def handle_info(:refresh, state) do
    new_state = %{state | most_recent_cli_release: fetch_release()}
    schedule_refresh()
    {:noreply, new_state}
  end

  def handle_call(:get_release, _from, state) do
    {:reply, Map.get(state, :most_recent_cli_release, nil), state}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp fetch_release do
    case Req.get(latest_cli_release_url()) do
      {:ok, %Req.Response{status: 200, body: release}} ->
        %{
          name: release["name"],
          published_at: Timex.parse!(release["published_at"], "{ISO:Extended}"),
          html_url: release["html_url"]
        }

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        nil

      {:error, _reason} ->
        nil
    end
  end
end
