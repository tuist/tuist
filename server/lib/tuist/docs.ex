defmodule Tuist.Docs do
  @moduledoc """
  Compile-time loaded documentation pages for the English docs site,
  plus runtime CLI pages fetched from the latest GitHub release.
  """

  alias Tuist.Docs.CLI
  alias Tuist.Docs.Loader

  {pages, source_paths} = Loader.load_pages!()

  for source_path <- source_paths do
    @external_resource source_path
  end

  @pages pages
  @pages_by_slug Map.new(@pages, &{&1.slug, &1})
  @slugs @pages_by_slug |> Map.keys() |> Enum.sort()

  def pages, do: @pages ++ cli_pages()
  def slugs, do: (@slugs ++ Enum.map(cli_pages(), & &1.slug)) |> Enum.sort()

  def get_page(path) when is_binary(path) do
    normalized = normalize_path(path)

    case Map.get(@pages_by_slug, normalized) do
      nil ->
        case cli_page(normalized) do
          nil -> fallback_to_english(normalized)
          page -> page
        end

      page ->
        page
    end
  end

  defp cli_pages, do: CLI.get_pages()

  defp cli_page(slug), do: CLI.get_page(slug)

  defp fallback_to_english(path) do
    segments = path |> Path.split() |> Enum.reject(&(&1 == "/"))

    case segments do
      [locale | rest] when locale != "en" ->
        en_slug = Path.join(["/en" | rest])
        Map.get(@pages_by_slug, en_slug) || cli_page(en_slug)

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
