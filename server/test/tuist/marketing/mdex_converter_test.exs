defmodule Tuist.Marketing.MDExConverterTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.MDExConverter

  test "renders Markdown tables with Noora styling and scrolling in static and live content" do
    table = """
    | Component | Release |
    | --- | ---: |
    | SDK (`{version}`) | [0.10.1](/releases/0.10.1) |
    """

    markdown = table <> "\nAnother table.\n\n" <> table

    {static_html, _template} = MDExConverter.compile_markdown(markdown, "static.md", false)

    for html <- [static_html, render_live(markdown)] do
      document = Floki.parse_fragment!(html)
      tables = Floki.find(document, ".noora-table[phx-hook=NooraTable]")
      assert length(tables) == 2

      ids = Floki.attribute(tables, "id")
      assert length(Enum.uniq(ids)) == 2

      for table <- tables do
        assert [_table] = Floki.find(table, "[data-part=scroll-container] > table")
        assert table |> Floki.find("th") |> Enum.map(&Floki.text/1) == ["Component", "Release"]
        assert table |> Floki.find("td code") |> Floki.text() == "{version}"
        assert table |> Floki.find("td a") |> Floki.attribute("href") == ["/releases/0.10.1"]
        assert [_scrollbar] = Floki.find(table, "[data-part=scrollbar-content]")
        assert [_thumb] = Floki.find(table, "[data-part=overlay-thumb]")
      end
    end

    {other_html, _template} = MDExConverter.compile_markdown(table, "other.md", false)
    [other_id] = other_html |> Floki.parse_fragment!() |> Floki.attribute("id")
    ids = static_html |> Floki.parse_fragment!() |> Floki.attribute("id")

    refute other_id in ids
  end

  describe "compile_markdown/3 for live posts" do
    test "renders code blocks whose content contains curly braces" do
      markdown = """
      ```json
      {"headers": {"Authorization": ["Bearer <token>"]}}
      ```
      """

      html = render_live(markdown)

      assert html =~ "Authorization"
    end

    test "renders mermaid diagrams whose content contains curly braces" do
      markdown = """
      ```mermaid
      graph LR
        A{decision} --> B
      ```
      """

      html = render_live(markdown)

      assert html =~ "A{decision}"
    end
  end

  defp render_live(markdown) do
    {_html, template} = MDExConverter.compile_markdown(markdown, "live.md", true)
    {rendered, _binding} = Code.eval_quoted(template, [assigns: %{}], __ENV__)

    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
