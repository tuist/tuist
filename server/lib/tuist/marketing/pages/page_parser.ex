defmodule Tuist.Marketing.Pages.PageParser do
  @moduledoc ~S"""
  This module contains the logic for parsing each page file.
  Pages are markdown files with YAML frontmatter that contain static content
  like the homepage, about page, etc.
  """

  def parse(path, contents) do
    [frontmatter_string, body] =
      contents |> String.replace(~r/^---\n/, "") |> String.split(["\n---\n"])

    frontmatter =
      frontmatter_string
      |> YamlElixir.read_from_string!()
      |> Map.put("slug", "/#{path |> Path.basename() |> String.replace(".md", "")}")

    {frontmatter, body}
  end
end
