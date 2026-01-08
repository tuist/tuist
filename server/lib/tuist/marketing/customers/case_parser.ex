defmodule Tuist.Marketing.Customers.CaseParser do
  @moduledoc false
  def parse(_path, contents) do
    [frontmatter_string, body] =
      contents |> String.replace(~r/^---\n/, "") |> String.split(["\n---\n"], parts: 2)

    frontmatter = YamlElixir.read_from_string!(frontmatter_string)

    {frontmatter, body}
  end
end
