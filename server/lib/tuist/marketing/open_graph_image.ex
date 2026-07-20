defmodule Tuist.Marketing.OpenGraphImage do
  @moduledoc """
  Resolves marketing image paths into content-addressed runtime render specifications.
  """

  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Changelog
  alias Tuist.Marketing.Changelog.OgImage, as: ChangelogOgImage
  alias Tuist.Marketing.Newsletter
  alias Tuist.Marketing.OgImages
  alias Tuist.Marketing.OpenGraph
  alias Tuist.Marketing.Pages
  alias Tuist.OpenGraphImageRenderer
  alias Tuist.OpenGraphImages

  @path_prefix "/marketing/images/og/generated/"
  @locales Tuist.Locale.supported_locales()

  @pages [
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

  def versioned_path(path) do
    case resolve(path) do
      {:ok, spec} -> OpenGraphImages.versioned_path(path, spec.key)
      :error -> path
    end
  end

  def resolve(path) do
    with true <- String.starts_with?(path, @path_prefix),
         relative_path = String.replace_prefix(path, @path_prefix, ""),
         segments when segments != [] <- String.split(relative_path, "/", trim: true),
         {locale, image_segments} <- locale_and_segments(segments) do
      resolve_segments(image_segments, locale)
    else
      _ -> :error
    end
  end

  defp locale_and_segments([locale | rest] = segments) do
    if locale != "en" and locale in @locales do
      {locale, rest}
    else
      {"en", segments}
    end
  end

  defp resolve_segments(["home.jpg"], locale), do: home_spec(locale)

  defp resolve_segments(["changelog", filename], "en") do
    with {:ok, id} <- jpg_stem(filename),
         entry when not is_nil(entry) <- Changelog.get_entry_by_id(id) do
      {:ok, changelog_entry_spec(entry)}
    else
      _ -> :error
    end
  end

  defp resolve_segments(["newsletter", "issues", filename], "en") do
    with {:ok, issue_number} <- jpg_stem(filename),
         issue when not is_nil(issue) <- Enum.find(Newsletter.issues(), &(to_string(&1.number) == issue_number)) do
      {:ok, libvips_spec("newsletter:v2", [issue.full_title], issue.full_title)}
    else
      _ -> :error
    end
  end

  defp resolve_segments(["blog" | _rest] = segments, "en") do
    generated_path = "/" <> Enum.join(segments, "/")

    with true <- String.ends_with?(generated_path, ".jpg"),
         post_path = String.replace_suffix(generated_path, ".jpg", ""),
         post when not is_nil(post) <- Enum.find(Blog.get_posts(), &(&1.slug == post_path)),
         nil <- post.og_image_path do
      {:ok, libvips_spec("blog-post:v2", [post.slug, post.title], post.title)}
    else
      _ -> :error
    end
  end

  defp resolve_segments([filename], locale) do
    case jpg_stem(filename) do
      {:ok, name} ->
        case Enum.find(@pages, fn {page_name, _title, _opts} -> page_name == name end) do
          {^name, title_message, opts} ->
            title = localized_title(title_message, locale)
            {:ok, page_spec(name, title, locale, opts)}

          nil ->
            dynamic_page_spec(name, locale)
        end

      _ ->
        :error
    end
  end

  defp resolve_segments(_segments, _locale), do: :error

  defp dynamic_page_spec(name, locale) do
    case Enum.find(Pages.get_pages(), fn page -> List.last(String.split(page.slug, "/")) == name end) do
      nil -> :error
      page -> {:ok, page_spec(name, page.title, locale, [])}
    end
  end

  defp page_spec(name, title, locale, opts) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    background_path = Path.join(priv_dir, "static/marketing/images/background.webp")
    template = Keyword.get(opts, :template, :default)

    icon_path =
      case Keyword.get(opts, :icon_path_suffix) do
        nil -> nil
        suffix -> Path.join(priv_dir, suffix)
      end

    key_parts = [
      "marketing-page:v2",
      Atom.to_string(template),
      locale,
      title,
      icon_path && {:file, icon_path},
      shared_asset_hash()
    ]

    OpenGraphImages.spec(key_parts, fn ->
      html_opts = [title: title, fonts_dir: fonts_dir, logo_path: logo_path, bg_path: background_path]
      html_opts = if icon_path, do: Keyword.put(html_opts, :icon_path, icon_path), else: html_opts
      html = render_template_html(template, html_opts, priv_dir)
      OpenGraphImageRenderer.render(html, title || name)
    end)
  end

  defp home_spec(locale) do
    title =
      localized_title("Your mobile platform team,", locale) <>
        " " <> localized_title("as a service", locale)

    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    phone_path = Path.join(priv_dir, "static/marketing/images/og/phone.png")

    {:ok,
     OpenGraphImages.spec(["marketing-home:v2", locale, title, shared_asset_hash()], fn ->
       html =
         OgImages.render_home_html(
           title: title,
           fonts_dir: fonts_dir,
           logo_path: logo_path,
           phone_path: phone_path
         )

       OpenGraphImageRenderer.render(html, title)
     end)}
  end

  defp changelog_entry_spec(entry) do
    priv_dir = Application.app_dir(:tuist, "priv")
    fonts_dir = Path.join(priv_dir, "static/fonts")
    logo_path = Path.join(priv_dir, "docs/images/logo.webp")
    date = Timex.format!(entry.date, "{Mfull} {D}, {YYYY}")

    key_parts = [
      "marketing-changelog-entry:v2",
      entry.id,
      entry.title,
      entry.description || "",
      date,
      entry.pull_request || "",
      changelog_asset_hash()
    ]

    OpenGraphImages.spec(key_parts, fn ->
      html =
        ChangelogOgImage.render_html(
          title: entry.title,
          description: entry.description,
          date: date,
          pull_request: entry.pull_request,
          fonts_dir: fonts_dir,
          logo_path: logo_path
        )

      OpenGraphImageRenderer.render(html, entry.title)
    end)
  end

  defp libvips_spec(kind, attributes, title) do
    OpenGraphImages.spec([kind | attributes] ++ [libvips_asset_hash()], fn ->
      OpenGraph.generate_og_image_binary(title)
    end)
  end

  defp render_template_html(:blog, opts, _priv_dir), do: OgImages.render_blog_html(opts)

  defp render_template_html(:changelog, opts, priv_dir) do
    timeline_path = Path.join(priv_dir, "static/marketing/images/og/changelog-timeline.svg")
    OgImages.render_changelog_list_html(Keyword.put(opts, :timeline_path, timeline_path))
  end

  defp render_template_html(:newsletter, opts, _priv_dir), do: OgImages.render_newsletter_html(opts)
  defp render_template_html(:api_docs, opts, _priv_dir), do: OgImages.render_api_docs_html(opts)
  defp render_template_html(:default, opts, _priv_dir), do: OgImages.render_html(opts)

  defp shared_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:marketing_open_graph_assets, [
      {:module, OgImages},
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")},
      {:file, Path.join(priv_dir, "static/marketing/images/background.webp")},
      {:file, Path.join(priv_dir, "static/marketing/images/og/phone.png")},
      {:file, Path.join(priv_dir, "static/marketing/images/og/changelog-timeline.svg")}
    ])
  end

  defp changelog_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:marketing_changelog_open_graph_assets, [
      {:module, ChangelogOgImage},
      {:dir, Path.join(priv_dir, "static/fonts")},
      {:file, Path.join(priv_dir, "docs/images/logo.webp")}
    ])
  end

  defp libvips_asset_hash do
    priv_dir = Application.app_dir(:tuist, "priv")

    OpenGraphImages.cached_key(:marketing_libvips_open_graph_assets, [
      {:module, OpenGraph},
      {:file, Path.join(priv_dir, "static/images/og_template.png")},
      {:dir, Path.join(priv_dir, "static/fonts")}
    ])
  end

  defp localized_title(title, locale) do
    Gettext.with_locale(TuistWeb.Gettext, locale, fn ->
      Gettext.dgettext(TuistWeb.Gettext, "marketing", title)
    end)
  end

  defp jpg_stem(filename) do
    if String.ends_with?(filename, ".jpg") do
      {:ok, String.replace_suffix(filename, ".jpg", "")}
    else
      :error
    end
  end
end
