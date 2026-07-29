defmodule Tuist.OpenGraphImageRenderer do
  @moduledoc """
  Renders Open Graph images at runtime through a supervised headless browser pool.
  """

  alias Tuist.Marketing.OpenGraph

  require Logger

  @pool Tuist.OpenGraphImagePool
  @task_supervisor Tuist.OpenGraphImageRenderer.TaskSupervisor
  @render_timeout 60_000

  @doc """
  Child specification for the browser pool backing the renderer.

  `BrowseChrome.BrowserPool` is a NimblePool that warms its browsers eagerly, so
  a machine without a usable Chrome would otherwise abort the whole supervision
  tree at boot. Returning `:ignore` keeps the node booting without a pool and
  lets `render/2` degrade to the fallback renderer, which is the right trade for
  a feature that only backs social cards.
  """
  def child_spec(opts) do
    %{id: @pool, start: {__MODULE__, :start_pool, [opts]}, type: :worker}
  end

  def start_pool(opts \\ []) do
    case BrowseChrome.BrowserPool.start_link(name: @pool, pool_size: pool_size(opts)) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.warning("Open Graph image browser pool unavailable, falling back to libvips: #{inspect(reason)}")

        :ignore
    end
  end

  def render(html, fallback_title) do
    # async_nolink (not Task.async) so a crashing render only surfaces as a
    # {:exit, reason} we can fall back on, instead of the link killing the
    # calling HTTP request process before render_fallback/2 runs. A pool that
    # failed to start arrives here as an exit too, and degrades the same way.
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

    case OpenGraph.generate_og_image_binary(title) do
      {:ok, image} -> {:fallback, image}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pool_size(opts) do
    case Keyword.fetch(opts, :pool_size) do
      {:ok, pool_size} -> pool_size
      :error -> pool_size_from_environment()
    end
  end

  defp pool_size_from_environment do
    case Integer.parse(System.get_env("TUIST_OG_IMAGE_POOL_SIZE", "2")) do
      {pool_size, ""} when pool_size > 0 -> min(pool_size, 4)
      _ -> 2
    end
  end
end
