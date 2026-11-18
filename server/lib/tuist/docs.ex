defmodule Tuist.Docs do
  @moduledoc """
  Compile-time loaded documentation pages for the English docs site,
  plus runtime CLI pages fetched from the latest GitHub release.
  """

  use Tuist.Docs.Content

  alias Tuist.Docs.CLI
  alias Tuist.Docs.Loader
  alias Tuist.Docs.Paths

  def pages(locale) when is_binary(locale) do
    cli_pages = Enum.filter(cli_pages(), &(&1.slug == "/#{locale}" or String.starts_with?(&1.slug, "/#{locale}/")))
    static_pages(locale) ++ cli_pages
  end

  # Translations that are near-empty remnants of their English page (under 15%
  # of its text). Arabic is no longer translated, so they won't catch up on
  # their own. Readers can still open them, but they point search engines at
  # the English page and stay out of the sitemap and hreflang alternates.
  @near_empty_translations MapSet.new([
                             "/ar/guides/features/agentic-coding/mcp",
                             "/ar/guides/features/cache/xcode-cache",
                             "/ar/guides/integrations/gitforge/github"
                           ])

  def slugs, do: Enum.sort(static_slugs() ++ Enum.map(cli_pages(), & &1.slug))

  @doc """
  Slugs worth indexing: every page except near-empty translations.
  """
  def indexable_slugs, do: Enum.reject(slugs(), &MapSet.member?(@near_empty_translations, &1))

  @doc """
  The slug search engines should index for `slug`: the English page for a
  near-empty translation, otherwise the slug itself.
  """
  def canonical_slug(slug) do
    if MapSet.member?(@near_empty_translations, slug) do
      [_locale | rest] = String.split(slug, "/", trim: true)
      "/" <> Enum.join(["en" | rest], "/")
    else
      slug
    end
  end

  def validate_page!(source_path) when is_binary(source_path) do
    Loader.validate_page!(source_path)
  end

  def get_page(path) when is_binary(path) do
    normalized = normalize_path(path)

    case static_page(normalized) do
      nil ->
        case cli_page(normalized) do
          nil -> fallback_to_english(normalized)
          page -> page
        end

      page ->
        page
    end
  end

  def get_page(locale, path_segments) when is_binary(locale) and is_list(path_segments) do
    locale
    |> Paths.slug(path_segments)
    |> get_page()
  end

  defp cli_pages, do: CLI.get_pages()

  defp cli_page(slug), do: CLI.get_page(slug)

  defp fallback_to_english(path) do
    segments = path |> Path.split() |> Enum.reject(&(&1 == "/"))

    case segments do
      [locale | rest] when locale != "en" ->
        en_slug = Path.join(["/en" | rest])
        static_page(en_slug) || cli_page(en_slug)

      _ ->
        nil
    end
  end

  def normalize_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> ensure_leading_slash()
    |> String.trim_trailing("/")
    |> normalize_index_path()
  end

  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp normalize_index_path(""), do: "/"
  defp normalize_index_path("/index"), do: "/"

  defp normalize_index_path(path) do
    if String.ends_with?(path, "/index") do
      String.trim_trailing(path, "/index")
    else
      path
    end
  end
end
