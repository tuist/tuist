defmodule AtlasWeb.Docs.MarkdownTest do
  use ExUnit.Case, async: true
  use Mimic

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

  test "fenced code uses light and dark syntax colors without changing copy text" do
    for {language, source} <- [
          {"json", ~s({"title": "Prepare documents", "enabled": true})},
          {"javascript", "const enabled = true;"},
          {"bash", "printf '%s' hello"},
          {"yaml", "enabled: true"}
        ] do
      html = Markdown.render("```#{language}\n#{source}\n```")
      document = LazyHTML.from_fragment(html)
      assert html =~ "color: light-dark("
      refute Enum.empty?(LazyHTML.query(document, "[data-part=code] code span"))
      assert document |> LazyHTML.query("[data-part=code] code") |> LazyHTML.text() |> String.trim() == source
      assert document |> LazyHTML.query("[data-part=copy-source]") |> LazyHTML.text() == source
      assert Enum.count(LazyHTML.query(document, "[data-part=copy][aria-label='Copy code']")) == 1
    end
  end

  test "highlighted source cannot introduce HTML elements" do
    source = ~s|{"example": "<img src=x onerror=alert(1)><script>unsafe</script>"}|
    document = "```json\n#{source}\n```" |> Markdown.render() |> LazyHTML.from_fragment()
    assert Enum.empty?(LazyHTML.query(document, "img, script"))
    assert document |> LazyHTML.query("[data-part=code] code") |> LazyHTML.text() |> String.trim() == source
  end

  test "unsupported languages and unavailable parsers retain escaped source" do
    source = "<script>unsafe</script>"
    html = Markdown.render("```unknown-language\n#{source}\n```")
    assert html =~ "&lt;script&gt;unsafe&lt;/script&gt;"
    refute html =~ "<script>"

    stub(Lumis, :highlight, fn _, _ -> {:error, "Parser unavailable"} end)
    document = "```json\n#{source}\n```" |> Markdown.render() |> LazyHTML.from_fragment()
    assert Enum.empty?(LazyHTML.query(document, "script"))
    assert document |> LazyHTML.query("[data-part=code] code") |> LazyHTML.text() == source
    assert document |> LazyHTML.query("[data-part=copy-source]") |> LazyHTML.text() == source
  end

  test "large snippets skip highlighting without truncating display or copy text" do
    stub(Lumis, :highlight, fn _, _ -> flunk("Oversized snippets must not be highlighted") end)
    source = String.duplicate("<&>", 90_000)
    document = "```json\n#{source}\n```" |> Markdown.render() |> LazyHTML.from_fragment()
    assert document |> LazyHTML.query("[data-part=code] code") |> LazyHTML.text() == source
    assert document |> LazyHTML.query("[data-part=copy-source]") |> LazyHTML.text() == source
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
