defmodule Tuist.Docs.CLI do
  @moduledoc """
  Fetches and caches the CLI spec from the latest GitHub release,
  then generates documentation pages for each CLI command.
  """

  use GenServer

  alias Tuist.Docs.CLI.Renderer

  require Logger

  @name __MODULE__
  @repo "tuist/tuist"
  @refresh_interval :timer.hours(1)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def get_pages do
    GenServer.call(@name, :get_pages, 15_000)
  end

  def get_page(slug) do
    GenServer.call(@name, {:get_page, slug}, 15_000)
  end

  def sidebar_items do
    GenServer.call(@name, :sidebar_items, 15_000)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{pages: [], pages_by_slug: %{}, sidebar_items: [], spec: nil}
    {:ok, state, {:continue, :fetch}}
  end

  @impl true
  def handle_continue(:fetch, state) do
    {:noreply, do_fetch(state)}
  end

  @impl true
  def handle_call(:get_pages, _from, state) do
    {:reply, state.pages, state}
  end

  def handle_call({:get_page, slug}, _from, state) do
    {:reply, Map.get(state.pages_by_slug, slug), state}
  end

  def handle_call(:sidebar_items, _from, state) do
    {:reply, state.sidebar_items, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    {:noreply, do_fetch(state)}
  end

  defp do_fetch(state) do
    schedule_refresh()

    case fetch_spec() do
      {:ok, spec} ->
        pages = Renderer.build_pages(spec)
        pages_by_slug = Map.new(pages, &{&1.slug, &1})
        sidebar_items = Renderer.build_sidebar(spec)
        %{state | pages: pages, pages_by_slug: pages_by_slug, sidebar_items: sidebar_items, spec: spec}

      {:error, reason} ->
        Logger.warning("Failed to fetch CLI spec: #{inspect(reason)}")
        state
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp fetch_spec do
    with {:ok, tag} <- fetch_latest_cli_tag(),
         {:ok, spec} <- fetch_spec_json(tag) do
      {:ok, spec}
    end
  end

  defp fetch_latest_cli_tag do
    url = "https://api.github.com/repos/#{@repo}/releases?per_page=20"

    case Req.get(url, headers: github_headers()) do
      {:ok, %{status: 200, body: releases}} ->
        cli_release =
          Enum.find(releases, fn release ->
            tag = release["tag_name"] || ""
            not String.contains?(tag, "@")
          end)

        case cli_release do
          nil -> {:error, :no_cli_release}
          release -> {:ok, release["tag_name"]}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_spec_json(tag) do
    url = "https://github.com/#{@repo}/releases/download/#{tag}/tuist.spec.json"

    case Req.get(url, headers: github_headers()) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Jason.decode(body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_headers do
    token = System.get_env("GITHUB_TOKEN")

    base = [{"accept", "application/json"}, {"user-agent", "tuist-server"}]

    if token do
      [{"authorization", "Bearer #{token}"} | base]
    else
      base
    end
  end
end
