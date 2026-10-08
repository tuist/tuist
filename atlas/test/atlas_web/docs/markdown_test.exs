defmodule AtlasWeb.Docs.MarkdownTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.Docs.Markdown

  test "heading links use parsed text, exclude code, and remain unique" do
    source =
      "## Using `Foo` & **bar**\n\n```text\n## Not a heading\n```\n\n## Using `Foo` & **bar**\n\n> [!NOTE]\n> ## Nested\n"

    {html, headings} = Markdown.render_with_headings(source)

    assert headings == [
             %{title: "Using Foo & bar", id: "using-foo-bar"},
             %{title: "Using Foo & bar", id: "using-foo-bar-2"},
             %{title: "Nested", id: "nested"}
           ]

    document = LazyHTML.from_fragment(html)

    for heading <- headings do
      assert Enum.count(LazyHTML.query(document, "h2##{heading.id}")) == 1
    end

    assert Enum.count(LazyHTML.query(document, "h2")) == 3
  end

  test "tables retain inline markup inside Noora scroll regions" do
    document =
      "| Setting | Meaning |\n| --- | --- |\n| `GOOGLE_CLIENT_SECRET` | **Keep it private.** |"
      |> Markdown.render()
      |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(document, "[data-part=docs-table][phx-hook=NooraTable]")) == 1
    assert Enum.count(LazyHTML.query(document, "[data-part=scroll-container] table td code")) == 1
    assert Enum.count(LazyHTML.query(document, "table td strong")) == 1
    assert Enum.count(LazyHTML.query(document, "[data-part=scrollbar], [data-part=overlay-scrollbar]")) == 2
  end
end
