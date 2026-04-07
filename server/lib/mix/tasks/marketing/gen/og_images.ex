defmodule Mix.Tasks.Marketing.Gen.OgImages do
  @moduledoc ~S"""
  This task generates the open graph images dynamically for all the marketing routes
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix
  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Marketing.Changelog.OgImage, as: ChangelogOgImage
  alias Tuist.Marketing.OgImages
  alias Tuist.Marketing.OpenGraph

  # Available locales for OG image generation
  @locales ["en", "ko", "ru", "ja"]

  @pool Tuist.Marketing.OgImagePool

  # Marketing pages that get Carta-based OG images with localized titles.
  # Each entry is {filename, gettext_title, opts} where opts may include :icon_path_suffix.
  @carta_pages [
    {"about", "About Tuist", [icon_path_suffix: "static/marketing/images/about/logo.webp"]},
    {"pricing", "Pricing", [icon_path_suffix: "static/marketing/images/pricing/logo-og.svg"]},
    {"blog", "Blog", [template: :blog]},
    {"changelog", "Changelog", [template: :changelog]},
    {"tuist-digest", "Newsletter", [template: :newsletter, icon_path_suffix: "static/marketing/images/newsletter/envelope.webp"]},
    {"support", "Support", []},
    {"customers", "Customers", []},
    {"cache", "Cache", []},
    {"build-insights", "Build Insights", []},
    {"previews", "Previews", []},
    {"selective-testing", "Selective Testing", []},
    {"flaky-tests", "Flaky Tests", []},
    {"test-insights", "Test Insights", []},
    {"api-docs", "API Docs", [template: :api_docs]}
  ]

  def run(_args) do
    ensure_dependencies_started()

    pool_size = max(System.schedulers_online(), 4)
    {:ok, _} = Browse.start_link(@pool, implementation: BrowseChrome.Browser, pool_size: pool_size)

    og_images_directory =
      :tuist |> Application.app_dir("priv") |> Path.join("static/marketing/images/og/generated")

    # Newsletter issues and blog posts are English-only
    generate_newsletter_og_images(og_images_directory)
    generate_posts_og_images(og_images_directory)

    # Changelog entries use their own Carta template (English-only)
    generate_changelog_og_images(og_images_directory)

    # Dynamic pages from markdown (terms, privacy, cookies, etc.)
    generate_dynamic_pages_og_images(og_images_directory)

    # Carta-based OG images for all static marketing pages, localized
    generate_marketing_page_og_images(og_images_directory)

    # Home page uses a special layout with phone mockup
    generate_home_og_images(og_images_directory)
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

  defp generate_dynamic_pages_og_images(og_images_directory) do
    dynamic_pages = Tuist.Marketing.Pages.get_pages()

    for locale <- @locales do
      Gettext.put_locale(TuistWeb.Gettext, locale)

      Enum.each(dynamic_pages, fn page ->
        filename = page.slug |> String.split("/") |> List.last()

        render_carta_page(
          og_images_directory,
          filename,
          page.title,
          locale,
          nil
        )
      end)
    end
  end

  defp generate_marketing_page_og_images(og_images_directory) do
    priv_dir = Application.app_dir(:tuist, "priv")

    IO.puts("Generating Carta-based OG images for #{length(@carta_pages)} pages x #{length(@locales)} locales...")

    for locale <- @locales do
      Gettext.put_locale(TuistWeb.Gettext, locale)

      Enum.each(@carta_pages, fn {filename, title_msgid, opts} ->
        icon_path =
          case Keyword.get(opts, :icon_path_suffix) do
            nil -> nil
            suffix -> Path.join(priv_dir, suffix)
          end

        template = Keyword.get(opts, :template, :default)

        render_carta_page(
          og_images_directory,
          filename,
          Gettext.dgettext(TuistWeb.Gettext, "marketing", title_msgid),
          locale,
          icon_path,
          template
        )
      end)
    end
  end

  defp render_carta_page(og_images_directory, filename, title, locale, icon_path, template \\ :default) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    bg_path = Path.join(priv_dir, "static/marketing/images/background.webp")

    image_path =
      if locale == "en" do
        Path.join(og_images_directory, "#{filename}.jpg")
      else
        Path.join(og_images_directory, "#{locale}/#{filename}.jpg")
      end

    File.mkdir_p!(Path.dirname(image_path))

    html_opts = [
      title: title,
      fonts_dir: fonts_dir,
      logo_path: logo_path,
      bg_path: bg_path
    ]

    html_opts = if icon_path, do: Keyword.put(html_opts, :icon_path, icon_path), else: html_opts

    html =
      case template do
        :blog -> OgImages.render_blog_html(html_opts)
        :changelog ->
          timeline_path = Path.join(priv_dir, "static/marketing/images/og/changelog-timeline.svg")
          OgImages.render_changelog_list_html(Keyword.put(html_opts, :timeline_path, timeline_path))
        :newsletter -> OgImages.render_newsletter_html(html_opts)
        :api_docs -> OgImages.render_api_docs_html(html_opts)
        _ -> OgImages.render_html(html_opts)
      end

    case Carta.render(@pool, html, width: 1920, height: 1080, quality: 95) do
      {:ok, jpeg_binary} ->
        File.write!(image_path, jpeg_binary)
        IO.puts("  Generated: #{Path.relative_to(image_path, File.cwd!())}")

      {:error, reason} ->
        IO.warn("Failed to generate OG image for #{filename} (#{locale}): #{inspect(reason)}")
    end
  end

  defp generate_home_og_images(og_images_directory) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    phone_path = Path.join(priv_dir, "static/marketing/images/og/phone.png")

    IO.puts("Generating Home OG images for #{length(@locales)} locales...")

    for locale <- @locales do
      Gettext.put_locale(TuistWeb.Gettext, locale)

      title =
        Gettext.dgettext(TuistWeb.Gettext, "marketing", "Your mobile platform team,") <>
          " " <> Gettext.dgettext(TuistWeb.Gettext, "marketing", "as a service")

      image_path =
        if locale == "en" do
          Path.join(og_images_directory, "home.jpg")
        else
          Path.join(og_images_directory, "#{locale}/home.jpg")
        end

      File.mkdir_p!(Path.dirname(image_path))

      html =
        OgImages.render_home_html(
          title: title,
          fonts_dir: fonts_dir,
          logo_path: logo_path,
          phone_path: phone_path
        )

      case Carta.render(@pool, html, width: 1920, height: 1080, quality: 95) do
        {:ok, jpeg_binary} ->
          File.write!(image_path, jpeg_binary)
          IO.puts("  Generated: #{Path.relative_to(image_path, File.cwd!())}")

        {:error, reason} ->
          IO.warn("Failed to generate Home OG image for #{locale}: #{inspect(reason)}")
      end
    end
  end

  defp generate_changelog_og_images(og_images_directory) do
    entries = Tuist.Marketing.Changelog.get_entries()
    pool_size = max(System.schedulers_online(), 4)

    fonts_dir = :tuist |> Application.app_dir("priv") |> Path.join("static/fonts")
    logo_path = :tuist |> Application.app_dir("priv") |> Path.join("docs/images/logo.webp")

    IO.puts("Generating OG images for #{length(entries)} changelog entries (pool_size: #{pool_size})...")

    entries
    |> Task.async_stream(
      fn entry ->
        image_path = Path.join(og_images_directory, "changelog/#{entry.id}.jpg")
        File.mkdir_p!(Path.dirname(image_path))

        date = Timex.format!(entry.date, "{Mfull} {D}, {YYYY}")

        html =
          ChangelogOgImage.render_html(
            title: entry.title,
            description: entry.description,
            date: date,
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
