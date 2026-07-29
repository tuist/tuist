defmodule Tuist.Mix.OgImageRenderer do
  @moduledoc """
  Build-time OG image renderer shared by the docs and marketing Mix tasks.
  """
  alias Tuist.Marketing.OgImageCache
  alias Tuist.Marketing.OpenGraph

  @max_pool_size 4
  @preflight_timeout 45_000
  @render_timeout 120_000
  @stream_timeout @render_timeout + 10_000

  def pool_size do
    case System.get_env("TUIST_OG_IMAGE_POOL_SIZE") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {pool_size, ""} when pool_size > 0 -> pool_size
          _ -> default_pool_size()
        end

      _ ->
        default_pool_size()
    end
  end

  def render_timeout, do: @stream_timeout

  def start_carta(pool) do
    pool_size = pool_size()

    case Browse.start_link(pool, implementation: BrowseChrome.Browser, pool_size: pool_size) do
      {:ok, pid} ->
        renderer = %{mode: :carta, pid: pid, pool: pool, pool_size: pool_size}

        case preflight_carta(renderer) do
          :ok ->
            renderer

          {:error, reason} ->
            stop_pool(pid)
            warn_fallback(reason)
            %{renderer | mode: :fallback, pid: nil}
        end

      {:error, reason} ->
        warn_fallback(reason)
        %{mode: :fallback, pid: nil, pool: pool, pool_size: pool_size}
    end
  end

  def render(renderer, html, image_path, key, label, fallback_title, opts \\ []) do
    carta_key = key
    fallback_key = fallback_cache_key(key)

    cond do
      OgImageCache.hit?(image_path, carta_key) ->
        log_cached(image_path)

      renderer.mode == :fallback and OgImageCache.hit?(image_path, fallback_key) ->
        log_cached(image_path)

      renderer.mode == :carta ->
        render_with_carta(renderer, html, image_path, carta_key, fallback_key, label, fallback_title, opts)

      true ->
        render_with_libvips(image_path, fallback_key, fallback_title)
    end
  end

  def warn_on_task_exit({:ok, _result}, _label), do: :ok

  def warn_on_task_exit({:exit, reason}, label) do
    IO.warn("Failed to generate #{label}: #{inspect(reason)}")
  end

  defp default_pool_size do
    System.schedulers_online()
    |> min(@max_pool_size)
    |> max(1)
  end

  defp preflight_carta(renderer) do
    fn ->
      do_render_with_carta(
        renderer.pool,
        "<!doctype html><html><body>ok</body></html>",
        width: 1,
        height: 1,
        quality: 50
      )
    end
    |> run_with_timeout(@preflight_timeout)
    |> case do
      {:ok, _jpeg} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp render_with_carta(renderer, html, image_path, carta_key, fallback_key, label, fallback_title, opts) do
    carta_opts =
      Keyword.merge(
        [
          width: 1920,
          height: 1080,
          quality: 95
        ],
        opts
      )

    case run_with_timeout(fn -> do_render_with_carta(renderer.pool, html, carta_opts) end, @render_timeout) do
      {:ok, jpeg_binary} ->
        File.write!(image_path, jpeg_binary)
        OgImageCache.put(image_path, carta_key)
        log_generated(image_path)

      {:error, reason} ->
        IO.warn("Failed to generate OG image for #{label} with Carta: #{inspect(reason)}. Falling back to libvips.")
        render_with_libvips(image_path, fallback_key, fallback_title)
    end
  end

  defp do_render_with_carta(pool, html, opts) do
    Carta.render(pool, html, opts)
  rescue
    exception -> {:error, {exception.__struct__, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp render_with_libvips(image_path, key, fallback_title) do
    OpenGraph.generate_og_image(fallback_title, image_path)
    OgImageCache.put(image_path, key)
    log_generated(image_path)
  end

  defp run_with_timeout(fun, timeout) do
    task = Task.async(fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> {:error, :timeout}
    end
  end

  defp fallback_cache_key(key), do: OgImageCache.key(["libvips-fallback:v1", key])

  defp stop_pool(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 5_000)
    end
  catch
    :exit, _reason -> :ok
  end

  defp warn_fallback(reason) do
    IO.warn("Chrome OG image renderer unavailable: #{inspect(reason)}. Falling back to libvips.")
  end

  defp log_cached(image_path), do: IO.puts("  Cached: #{relative_path(image_path)}")

  defp log_generated(image_path), do: IO.puts("  Generated: #{relative_path(image_path)}")

  defp relative_path(image_path), do: Path.relative_to(image_path, File.cwd!())
end
