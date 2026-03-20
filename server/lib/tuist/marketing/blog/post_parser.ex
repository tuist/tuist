defmodule Tuist.Marketing.Blog.PostParser do
  @moduledoc ~S"""
  This module contains the logic for parsing each blog post file.
  """

  alias Tuist.Marketing.MDExConverter

  def parse(path, contents) do
    [frontmatter_string, body] =
      contents |> String.replace(~r/^---\n/, "") |> String.split(["\n---\n"], parts: 2)

    frontmatter = YamlElixir.read_from_string!(frontmatter_string)

    {body_html, body_template} = MDExConverter.compile_markdown(body, path, frontmatter["live"] || false)

    date_string = get_date_string_from_path(path)
    date = date_string |> Timex.parse!("{YYYY}/{M}/{D}") |> Timex.to_datetime("Etc/UTC")

    frontmatter =
      Map.merge(frontmatter, %{
        "slug" =>
          "/blog/#{date_string}/#{path |> Path.basename() |> String.replace(".md", "") |> String.replace(".", "")}",
        "date" => date,
        "body_template" => body_template
      })

    # /blog/2024/09/28/kamal-two-swift-server
    {frontmatter, body_html}
  end

  defp get_date_string_from_path(path) do
    path
    |> Path.dirname()
    |> String.split("/")
    |> Enum.reverse()
    |> Enum.take(3)
    |> Enum.reverse()
    |> Enum.join("/")
  end
end
