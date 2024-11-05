defmodule Tuist.Changelog.EntryParser do
  @moduledoc ~S"""
  This module is responsible for parsing changelog entries from markdown files.
  """

  def parse(path, contents) do
    [frontmatter_string, body] =
      contents |> String.replace(~r/^---\n/, "") |> String.split(["\n---\n"])

    date_string = get_date_string_from_path(path)
    date = date_string |> Timex.parse!("{YYYY}/{M}/{D}") |> Timex.to_datetime("Etc/UTC")

    id =
      Path.basename(path)
      |> String.replace(".md", "")
      |> String.replace_prefix(".", "-")

    frontmatter =
      YamlElixir.read_from_string!(frontmatter_string)
      |> Map.merge(%{
        "id" => id,
        "date" => date
      })

    {frontmatter, body}
  end

  defp get_date_string_from_path(path) do
    Path.basename(path)
    |> String.replace(".md", "")
    |> String.split("-")
    |> List.first()
    |> String.replace(".", "/")
  end
end
