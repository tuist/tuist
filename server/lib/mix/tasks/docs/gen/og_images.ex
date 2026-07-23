defmodule Mix.Tasks.Docs.Gen.OgImages do
  @moduledoc """
  Generates open graph images for all documentation pages.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  alias Tuist.Docs
  alias Tuist.Docs.OgImage
  alias Tuist.Docs.Sidebar
  alias Tuist.Marketing.OgImageCache
  alias Tuist.Mix.OgImageRenderer

  @pool Tuist.Docs.OgImagePool

  def run(_args) do
    ensure_dependencies_started()

    output_dir =
      :tuist |> Application.app_dir("priv") |> Path.join("docs/images/og/generated")

    File.mkdir_p!(output_dir)

    fonts_dir =
      :tuist |> Application.app_dir("priv") |> Path.join("static/fonts")

    logo_path =
      :tuist |> Application.app_dir("priv") |> Path.join("docs/images/logo.webp")

    renderer = OgImageRenderer.start_carta(@pool)
    pool_size = renderer.pool_size

    category_map = build_category_map()

    # Hash assets shared across all docs OG renders once. Per-image cache keys
    # mix this in so a font / logo swap correctly invalidates everything.
    asset_hash =
      OgImageCache.key([
        "docs-asset-bundle:v1",
        {:dir, fonts_dir},
        {:file, logo_path}
      ])

    pages = Docs.pages()
    IO.puts("Generating OG images for #{length(pages)} docs pages (pool_size: #{pool_size})...")

    pages
    |> Task.async_stream(
      fn page ->
        slug = page.slug
        filename = OgImage.slug_to_filename(slug)
        image_path = Path.join(output_dir, filename)

        en_slug = String.replace(slug, ~r{^/[^/]+/}, "/en/")
        category = Map.get(category_map, en_slug, "Docs")

        html =
          OgImage.render_html(
            title: page.title,
            description: page.description,
            category: category,
            fonts_dir: fonts_dir,
            logo_path: logo_path
          )

        File.mkdir_p!(Path.dirname(image_path))

        key =
          OgImageCache.key([
            "docs-page:v1",
            slug,
            page.title || "",
            page.description || "",
            category,
            asset_hash
          ])

        OgImageRenderer.render(renderer, html, image_path, key, slug, page.title || category || "Tuist")
      end,
      max_concurrency: pool_size,
      on_timeout: :kill_task,
      timeout: OgImageRenderer.render_timeout()
    )
    |> Enum.each(&OgImageRenderer.warn_on_task_exit(&1, "docs OG image"))
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
