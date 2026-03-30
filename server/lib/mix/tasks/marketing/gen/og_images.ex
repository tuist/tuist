defmodule Mix.Tasks.Marketing.Gen.OgImages do
  @moduledoc ~S"""
  This task generates the open graph images dynamically for all the marketing routes
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix
  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Marketing.Changelog.OgImage, as: ChangelogOgImage
  alias Tuist.Marketing.OpenGraph

  # Available locales for OG image generation
  @locales ["en", "ko", "ru", "ja"]

  @pool Tuist.Marketing.OgImagePool

  def run(_args) do
    ensure_dependencies_started()

    og_images_directory =
      :tuist |> Application.app_dir("priv") |> Path.join("static/marketing/images/og/generated")

    # Newsletter, blog posts, and changelog are English-only, so no localization needed
    generate_newsletter_og_images(og_images_directory)
    generate_posts_og_images(og_images_directory)
    generate_changelog_og_images(og_images_directory)

    # Pages need to be generated for all locales
    generate_pages_og_images(og_images_directory)
  end

  defp ensure_dependencies_started do
    Application.ensure_all_started(:telemetry)
    Application.ensure_all_started(:briefly)
  end

  defp generate_newsletter_og_images(og_images_directory) do
    Enum.each(Tuist.Marketing.Newsletter.issues(), fn issue ->
      OpenGraph.generate_og_image(
        issue.full_title,
        Path.join(og_images_directory, "newsletter/issues/#{issue.number}.jpg")
      )
    end)
  end

  defp generate_pages_og_images(og_images_directory) do
    dynamic_pages = Tuist.Marketing.Pages.get_pages()

    # Generate OG images for all locales
    for locale <- @locales do
      # Set the locale for gettext
      Gettext.put_locale(TuistWeb.Gettext, locale)

      # Generate images for dynamic pages (these use the page title from markdown)
      Enum.each(dynamic_pages, fn page ->
        OpenGraph.generate_og_image(
          page.title,
          Path.join(og_images_directory, "#{page.slug |> String.split("/") |> List.last()}.jpg"),
          locale
        )
      end)

      # Generate images for static pages with localized titles
      OpenGraph.generate_og_image(
        dgettext("marketing", "About us"),
        Path.join(og_images_directory, "about.jpg"),
        locale
      )

      OpenGraph.generate_og_image(
        dgettext("marketing", "Tuist Digest Newsletter"),
        Path.join(og_images_directory, "tuist-digest.jpg"),
        locale
      )

      OpenGraph.generate_og_image(
        dgettext("marketing", "Support"),
        Path.join(og_images_directory, "support.jpg"),
        locale
      )
    end
  end

  defp generate_changelog_og_images(og_images_directory) do
    entries = Tuist.Marketing.Changelog.get_entries()
    pool_size = max(System.schedulers_online(), 4)

    {:ok, _} = Browse.start_link(@pool, implementation: BrowseChrome.Browser, pool_size: pool_size)

    fonts_dir = :tuist |> Application.app_dir("priv") |> Path.join("static/fonts")
    logo_path = :tuist |> Application.app_dir("priv") |> Path.join("docs/images/logo.webp")

    IO.puts("Generating OG images for #{length(entries)} changelog entries (pool_size: #{pool_size})...")

    entries
    |> Task.async_stream(
      fn entry ->
        image_path = Path.join(og_images_directory, "changelog/#{entry.id}.jpg")
        File.mkdir_p!(Path.dirname(image_path))

        html =
          ChangelogOgImage.render_html(
            title: entry.title,
            description: entry.description,
            pull_request: entry.pull_request,
            fonts_dir: fonts_dir,
            logo_path: logo_path
          )

        case Carta.render(@pool, html, width: 1920, height: 1080, quality: 95) do
          {:ok, jpeg_binary} ->
            File.write!(image_path, jpeg_binary)
            IO.puts("  Generated: #{Path.relative_to(image_path, File.cwd!())}")

          {:error, reason} ->
            IO.warn("Failed to generate OG image for #{entry.id}: #{inspect(reason)}")
        end
      end,
      max_concurrency: pool_size,
      timeout: 30_000
    )
    |> Stream.run()
  end

  defp generate_posts_og_images(og_images_directory) do
    Enum.each(Tuist.Marketing.Blog.get_posts(), fn post ->
      image_path = Path.join(og_images_directory, "#{post.slug}.jpg")

      IO.puts("Generating OG image for '#{post.title}' at #{Path.relative_to(image_path, File.cwd!())}")

      File.mkdir_p!(Path.dirname(image_path))

      OpenGraph.generate_og_image(
        post.title,
        image_path
      )
    end)
  end
end
