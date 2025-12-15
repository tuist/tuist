defmodule Tuist.Marketing.CaseStudies.CaseParser do
  def parse(_path, contents) do
    [frontmatter_string, body] =
      contents |> String.replace(~r/^---\n/, "") |> String.split(["\n---\n"], parts: 2)

    frontmatter =
      frontmatter_string
      |> YamlElixir.read_from_string!()

    {frontmatter, body}
  end
end
