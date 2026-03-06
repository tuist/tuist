defmodule Tuist.Docs do
  @moduledoc """
  Compile-time loaded documentation pages for the English docs site.
  """

  alias Tuist.Docs.Loader

  {pages, source_paths} = Loader.load_pages!()

  for source_path <- source_paths do
    @external_resource source_path
  end

  @pages pages
  @pages_by_slug Map.new(@pages, &{&1.slug, &1})
  @slugs @pages_by_slug |> Map.keys() |> Enum.sort()

  def pages, do: @pages
  def slugs, do: @slugs

  def get_page(path) when is_binary(path) do
    path
    |> normalize_path()
    |> then(&Map.get(@pages_by_slug, &1))
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
