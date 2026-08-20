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

  Returning `:ignore` on a `start_link/1` error keeps the node booting without a
  pool and lets `render/2` degrade to the fallback renderer, which is the right
  trade for a feature that only backs social cards.

  This does not cover a missing Chrome. `BrowseChrome.BrowserPool` warms its
  browsers eagerly, but NimblePool absorbs an `init_worker/1` raise and retries
  it forever instead of failing `start_link/1`, so the pool must not be started
  at all on a host without Chrome — see
  `Tuist.Application.RuntimeChildren.open_graph_image_renderer/1`.
  """
  def child_spec(opts) do
    %{id: @pool, start: {__MODULE__, :start_pool, [opts]}, type: :worker}
  end

  def start_pool(opts \\ []) do
    pool_opts = maybe_put_chrome_path([name: @pool, pool_size: pool_size(opts)], chrome_path(opts))

    case BrowseChrome.BrowserPool.start_link(pool_opts) do
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
    run_render(fallback_title, fn ->
      Carta.render(@pool, html, width: 1920, height: 1080, quality: 95)
    end)
  end

  @doc false
  # Runs `render_fun` in a supervised task and degrades to the fallback renderer
  # on any failure. `async_nolink` keeps a crashing render from killing the
  # calling HTTP request; it surfaces here as a `{:exit, reason}` we fall back on.
  #
  # We trap the exit inside the task because a saturated pool makes
  # `NimblePool.checkout!` exit, and `Task.Supervised` logs a "Task ...
  # terminating" report for every such exit, flooding Sentry (TUIST-3R8) even
  # though the fallback already handles it. Returning `{:error, reason}` lets
  # the task exit cleanly while still logging one warning with the reason.
  def run_render(fallback_title, render_fun) do
    task =
      Task.Supervisor.async_nolink(@task_supervisor, fn ->
        try do
          render_fun.()
        catch
          :exit, reason -> {:error, reason}
        end
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

  defp maybe_put_chrome_path(pool_opts, nil), do: pool_opts
  defp maybe_put_chrome_path(pool_opts, path), do: Keyword.put(pool_opts, :chrome_path, path)

  # In the release image this points at the `og-chromium` wrapper, which gives
  # Chromium a writable HOME so `--headless=new` can bind its DevTools port.
  # Unset in dev, where BrowseChrome auto-detects the local Chrome.
  defp chrome_path(opts) do
    case Keyword.get(opts, :chrome_path) do
      nil -> chrome_path_from_environment()
      path -> path
    end
  end

  defp chrome_path_from_environment do
    case System.get_env("TUIST_OG_IMAGE_CHROME_PATH") do
      nil -> nil
      "" -> nil
      path -> path
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
