defmodule Tuist.Marketing.Pages.PageParser do
  @moduledoc ~S"""
  This module contains the logic for parsing each page file.
  Pages are markdown files with YAML frontmatter that contain static content
  like the homepage, about page, etc.
  """

  alias Tuist.Marketing.MDExConverter

  def parse(path, contents) do
    [frontmatter_string, body] =
      contents |> String.replace(~r/^---\n/, "") |> String.split(["\n---\n"], parts: 2)

    frontmatter =
      frontmatter_string
      |> YamlElixir.read_from_string!()
      |> Map.put("slug", "/#{path |> Path.basename() |> String.replace(".md", "")}")

    {body_html, _body_template} = MDExConverter.compile_markdown(body, path, false)

    {frontmatter, body_html}
  end
end
