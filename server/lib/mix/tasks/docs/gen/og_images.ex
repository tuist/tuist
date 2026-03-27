defmodule Mix.Tasks.Docs.Gen.OgImages do
  @moduledoc """
  Generates open graph images for all documentation pages using Carta and BrowseChrome.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  alias Tuist.Docs
  alias Tuist.Docs.Sidebar

  @pool Tuist.Docs.OgImagePool

  def run(_args) do
    ensure_dependencies_started()

    output_dir =
      :tuist |> Application.app_dir("priv") |> Path.join("static/docs/images/og/generated")

    File.mkdir_p!(output_dir)

    fonts_dir =
      :tuist |> Application.app_dir("priv") |> Path.join("static/fonts")

    logo_path =
      :tuist |> Application.app_dir("priv") |> Path.join("static/docs/images/logo.webp")

    pool_size = System.schedulers_online() |> max(4)

    {:ok, _} = Browse.start_link(@pool, implementation: BrowseChrome.Browser, pool_size: pool_size)

    category_map = build_category_map()

    pages = Docs.pages()
    IO.puts("Generating OG images for #{length(pages)} docs pages (pool_size: #{pool_size})...")

    pages
    |> Task.async_stream(
      fn page ->
        slug = page.slug
        filename = Tuist.Docs.OgImage.slug_to_filename(slug)
        image_path = Path.join(output_dir, filename)

        locale = slug |> String.split("/", trim: true) |> List.first()
        en_slug = String.replace(slug, ~r{^/[^/]+/}, "/en/")
        category = Map.get(category_map, en_slug, "Docs")

        html =
          Tuist.Docs.OgImage.render_html(
            title: page.title,
            description: page.description,
            category: category,
            fonts_dir: fonts_dir,
            logo_path: logo_path
          )

        File.mkdir_p!(Path.dirname(image_path))

        case Carta.render(@pool, html, width: 1920, height: 1080, quality: 95) do
          {:ok, jpeg_binary} ->
            File.write!(image_path, jpeg_binary)
            IO.puts("  [#{locale}] Generated: #{Path.relative_to(image_path, File.cwd!())}")

          {:error, reason} ->
            IO.warn("Failed to generate OG image for #{slug}: #{inspect(reason)}")
        end
      end,
      max_concurrency: pool_size,
      timeout: 30_000
    )
    |> Stream.run()
  end

  # This task runs without the full application supervisor (e.g. during Docker builds
  # where no database or external services are available). We selectively start only
  # the dependencies needed for OG image generation:
  #
  # - :telemetry — required by Browse/BrowseChrome for instrumentation spans
  # - :briefly — used by Carta to write temporary HTML files for the browser
  # - :cachex — used by Tuist.Docs.CLI to cache CLI documentation pages fetched from GitHub
  # - :req — HTTP client used by Tuist.Docs.CLI to fetch CLI docs from GitHub releases
  # - Cachex :tuist store — the named cache instance that Tuist.Docs.CLI reads from
  defp ensure_dependencies_started do
    Application.ensure_all_started(:telemetry)
    Application.ensure_all_started(:briefly)
    Application.ensure_all_started(:cachex)
    Application.ensure_all_started(:req)
    {:ok, _} = Cachex.start(:tuist)
  end

  defp build_category_map do
    Sidebar.tree()
    |> Enum.flat_map(fn group ->
      collect_slugs_with_category(group.label || "Docs", group.items)
    end)
    |> Map.new()
  end

  defp collect_slugs_with_category(category, items) do
    Enum.flat_map(items, fn item ->
      own =
        if item.slug do
          [{item.slug, category}]
        else
          []
        end

      children = collect_slugs_with_category(category, item.items)
      own ++ children
    end)
  end
end
