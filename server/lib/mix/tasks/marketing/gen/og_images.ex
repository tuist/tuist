defmodule Mix.Tasks.Marketing.Gen.OgImages do
  @moduledoc ~S"""
  This task generates the open graph images dynamically for all the marketing routes
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix
  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Marketing.Changelog.OgImage, as: ChangelogOgImage
  alias Tuist.Marketing.OgImageCache
  alias Tuist.Marketing.OgImages
  alias Tuist.Marketing.OpenGraph

  # Available locales for OG image generation — must match Localization.all_locales()
  @locales ["en", "es", "ja", "ko", "ru", "yue_Hant", "zh_Hans", "zh_Hant"]

  @pool Tuist.Marketing.OgImagePool

  # Marketing pages that get Carta-based OG images with localized titles.
  # Each entry is {filename, gettext_title, opts} where opts may include :icon_path_suffix.
  @carta_pages [
    {"about", "About Tuist", [icon_path_suffix: "static/marketing/images/about/logo.webp"]},
    {"pricing", "Pricing", [icon_path_suffix: "static/marketing/images/pricing/logo-og.svg"]},
    {"blog", "Blog", [template: :blog]},
    {"changelog", "Changelog", [template: :changelog]},
    {"tuist-digest", "Newsletter",
     [template: :newsletter, icon_path_suffix: "static/marketing/images/newsletter/envelope.webp"]},
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

    # Hash all assets shared across renders once. Per-image cache keys mix this
    # in so a logo / font / template swap correctly invalidates everything.
    asset_hash = compute_asset_hash()
    libvips_asset_hash = compute_libvips_asset_hash()

    # Newsletter issues and blog posts are English-only
    generate_newsletter_og_images(og_images_directory, libvips_asset_hash)
    generate_posts_og_images(og_images_directory, libvips_asset_hash)

    # Changelog entries use their own Carta template (English-only)
    generate_changelog_og_images(og_images_directory, asset_hash)

    # Dynamic pages from markdown (terms, privacy, cookies, etc.)
    generate_dynamic_pages_og_images(og_images_directory, asset_hash)

    # Carta-based OG images for all static marketing pages, localized
    generate_marketing_page_og_images(og_images_directory, asset_hash)

    # Home page uses a special layout with phone mockup
    generate_home_og_images(og_images_directory, asset_hash)
  end

  defp compute_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OgImageCache.key([
      "marketing-asset-bundle:v1",
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")},
      {:file, Path.join(priv_dir, "static/marketing/images/background.webp")},
      {:file, Path.join(priv_dir, "static/marketing/images/og/phone.png")},
      {:file, Path.join(priv_dir, "static/marketing/images/og/changelog-timeline.svg")}
    ])
  end

  defp compute_libvips_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OgImageCache.key([
      "marketing-libvips-asset-bundle:v1",
      {:file, Path.join(priv_dir, "static/images/og_template.png")},
      {:dir, Path.join(priv_dir, "static/fonts")}
    ])
  end

  defp ensure_dependencies_started do
    Application.ensure_all_started(:telemetry)
    Application.ensure_all_started(:briefly)
  end

  defp generate_newsletter_og_images(og_images_directory, asset_hash) do
    Enum.each(Tuist.Marketing.Newsletter.issues(), fn issue ->
      image_path = Path.join(og_images_directory, "newsletter/issues/#{issue.number}.jpg")
      key = OgImageCache.key(["newsletter:v1", issue.full_title, asset_hash])

      generate_with_libvips(issue.full_title, image_path, key)
    end)
  end

  defp generate_dynamic_pages_og_images(og_images_directory, asset_hash) do
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
          nil,
          :default,
          asset_hash
        )
      end)
    end
  end

  defp generate_marketing_page_og_images(og_images_directory, asset_hash) do
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
          template,
          asset_hash
        )
      end)
    end
  end

  defp render_carta_page(og_images_directory, filename, title, locale, icon_path, template, asset_hash) do
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

    html = render_template_html(template, html_opts, priv_dir)

    icon_key_part =
      case icon_path do
        nil -> "no-icon"
        path -> {:file, path}
      end

    key =
      OgImageCache.key([
        "marketing-page:v1",
        Atom.to_string(template),
        locale,
        title,
        icon_key_part,
        asset_hash
      ])

    render_with_carta(html, image_path, key, "#{filename} (#{locale})")
  end

  defp render_template_html(:blog, html_opts, _priv_dir), do: OgImages.render_blog_html(html_opts)

  defp render_template_html(:changelog, html_opts, priv_dir) do
    timeline_path = Path.join(priv_dir, "static/marketing/images/og/changelog-timeline.svg")
    OgImages.render_changelog_list_html(Keyword.put(html_opts, :timeline_path, timeline_path))
  end

  defp render_template_html(:newsletter, html_opts, _priv_dir), do: OgImages.render_newsletter_html(html_opts)

  defp render_template_html(:api_docs, html_opts, _priv_dir), do: OgImages.render_api_docs_html(html_opts)

  defp render_template_html(_default, html_opts, _priv_dir), do: OgImages.render_html(html_opts)

  defp generate_home_og_images(og_images_directory, asset_hash) do
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

      key = OgImageCache.key(["home:v1", locale, title, asset_hash])

      render_with_carta(html, image_path, key, "home (#{locale})")
    end
  end

  defp generate_changelog_og_images(og_images_directory, asset_hash) do
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

        key =
          OgImageCache.key([
            "changelog-entry:v1",
            entry.id,
            entry.title,
            entry.description || "",
            date,
            entry.pull_request || "",
            asset_hash
          ])

        render_with_carta(html, image_path, key, "changelog #{entry.id}")
      end,
      max_concurrency: pool_size,
      timeout: 30_000
    )
    |> Stream.run()
  end

  defp generate_posts_og_images(og_images_directory, asset_hash) do
    Enum.each(Tuist.Marketing.Blog.get_posts(), fn post ->
      image_path = Path.join(og_images_directory, "#{post.slug}.jpg")
      File.mkdir_p!(Path.dirname(image_path))

      key = OgImageCache.key(["blog-post:v1", post.slug, post.title, asset_hash])

      generate_with_libvips(post.title, image_path, key)
    end)
  end

  # Render with Carta (headless Chromium) unless an existing cache key sidecar
  # matches. Cache hits skip the multi-second screenshot entirely.
  defp render_with_carta(html, image_path, key, label) do
    if OgImageCache.hit?(image_path, key) do
      IO.puts("  Cached: #{Path.relative_to(image_path, File.cwd!())}")
    else
      case Carta.render(@pool, html, width: 1920, height: 1080, quality: 95) do
        {:ok, jpeg_binary} ->
          File.write!(image_path, jpeg_binary)
          OgImageCache.put(image_path, key)
          IO.puts("  Generated: #{Path.relative_to(image_path, File.cwd!())}")

        {:error, reason} ->
          IO.warn("Failed to generate OG image for #{label}: #{inspect(reason)}")
      end
    end
  end

  # libvips-backed renders (newsletter / blog posts). Cheaper per call than
  # Carta but still worth caching since we run them many times.
  defp generate_with_libvips(title, image_path, key) do
    if OgImageCache.hit?(image_path, key) do
      IO.puts("  Cached: #{Path.relative_to(image_path, File.cwd!())}")
    else
      OpenGraph.generate_og_image(title, image_path)
      OgImageCache.put(image_path, key)
      IO.puts("  Generated: #{Path.relative_to(image_path, File.cwd!())}")
    end
  end
end
