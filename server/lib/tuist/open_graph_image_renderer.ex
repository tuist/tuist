defmodule Tuist.OpenGraphImageRenderer do
  @moduledoc """
  Lazily starts a headless browser pool and renders Open Graph images at runtime.
  """

  use GenServer

  alias Tuist.Marketing.OpenGraph

  require Logger

  @pool Tuist.OpenGraphImagePool
  @task_supervisor Tuist.OpenGraphImageRenderer.TaskSupervisor
  @render_timeout 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def render(html, fallback_title) do
    case GenServer.call(__MODULE__, :ensure_pool, @render_timeout) do
      :ok -> render_with_browser(html, fallback_title)
      {:error, reason} -> render_fallback(fallback_title, reason)
    end
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{pool_pid: nil}}
  end

  @impl true
  def handle_call(:ensure_pool, _from, %{pool_pid: pool_pid} = state) when is_pid(pool_pid) do
    if Process.alive?(pool_pid) do
      {:reply, :ok, state}
    else
      start_pool(state)
    end
  end

  def handle_call(:ensure_pool, _from, state), do: start_pool(state)

  @impl true
  def handle_info({:EXIT, pool_pid, _reason}, %{pool_pid: pool_pid} = state) do
    {:noreply, %{state | pool_pid: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_pool(state) do
    case Browse.start_link(@pool, implementation: BrowseChrome.Browser, pool_size: pool_size()) do
      {:ok, pool_pid} -> {:reply, :ok, %{state | pool_pid: pool_pid}}
      {:error, {:already_started, pool_pid}} -> {:reply, :ok, %{state | pool_pid: pool_pid}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp render_with_browser(html, fallback_title) do
    # async_nolink (not Task.async) so a crashing render only surfaces as a
    # {:exit, reason} we can fall back on, instead of the link killing the
    # calling HTTP request process before render_fallback/2 runs.
    task =
      Task.Supervisor.async_nolink(@task_supervisor, fn ->
        Carta.render(@pool, html, width: 1920, height: 1080, quality: 95)
      end)

    case Task.yield(task, @render_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, image}} -> {:ok, image}
      {:ok, {:error, reason}} -> render_fallback(fallback_title, reason)
      {:exit, reason} -> render_fallback(fallback_title, reason)
      nil -> render_fallback(fallback_title, :timeout)
    end
  end

  # Tagged :fallback (not :ok) so the caller can serve the generic image
  # without persisting it under the content-addressed immutable key. A
  # transient browser failure must not permanently poison the cache for a
  # page whose real render would otherwise succeed on a later request.
  defp render_fallback(title, reason) do
    Logger.warning("Headless browser Open Graph image rendering failed, using the fallback renderer: #{inspect(reason)}")

    {:fallback, OpenGraph.generate_og_image_binary(title)}
  rescue
    error -> {:error, error}
  end

  defp pool_size do
    case Integer.parse(System.get_env("TUIST_OG_IMAGE_POOL_SIZE", "2")) do
      {pool_size, ""} when pool_size > 0 -> min(pool_size, 4)
      _ -> 2
    end
  end
end
