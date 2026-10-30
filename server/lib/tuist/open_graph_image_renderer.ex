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

  A missing Chrome never reaches that branch. `BrowseChrome.BrowserPool` warms
  its browsers eagerly, but NimblePool absorbs an `init_worker/1` raise and
  retries it forever with no backoff instead of failing `start_link/1`. So
  `start_pool/1` resolves the Chrome executable first and returns `:ignore`
  when there is none.
  """
  def child_spec(opts) do
    %{id: @pool, start: {__MODULE__, :start_pool, [opts]}, type: :worker}
  end

  def start_pool(opts \\ []) do
    case find_chrome(chrome_path(opts)) do
      nil ->
        Logger.warning("Open Graph image browser pool not started, no Chrome executable found; falling back to libvips")

        :ignore

      chrome_path ->
        start_browser_pool(name: @pool, pool_size: pool_size(opts), chrome_path: chrome_path)
    end
  end

  defp start_browser_pool(pool_opts) do
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
      # Carta opens separate browser connections for the viewport override and
      # screenshot. Chrome clears the override when that connection closes.
      # Keep sizing, navigation and capture together in one browser session.
      BrowseChrome.checkout(@pool, fn browser ->
        case BrowseChrome.Chrome.capture(browser, html, width: 1920, height: 1080, quality: 95) do
          {:ok, _image} = result -> {result, :ok}
          {:error, _reason} = result -> {result, :remove}
        end
      end)
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

  defp find_chrome(nil), do: Enum.find(chrome_candidates(), &chrome_executable?/1)

  defp find_chrome(path) do
    if chrome_executable?(path), do: path
  end

  # Mirrors the private lookup in `BrowseChrome.Chrome`, which the pool would
  # otherwise run in every worker init.
  defp chrome_candidates do
    case :os.type() do
      {:unix, :darwin} ->
        [
          "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
          "/Applications/Chromium.app/Contents/MacOS/Chromium",
          "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
        ]

      _ ->
        ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser"]
    end
  end

  defp chrome_executable?(path), do: not is_nil(System.find_executable(path)) or File.exists?(path)

  # In the release image this points at the `og-chromium` wrapper, which gives
  # Chromium a writable HOME so `--headless=new` can bind its DevTools port.
  # Unset in dev, where `find_chrome/1` auto-detects the local Chrome.
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
