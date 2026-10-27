defmodule AtlasWeb.MarkdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AtlasWeb.Markdown

  test "renders mermaid code blocks as diagrams" do
    html =
      render_component(&Markdown.content/1,
        id: "body",
        body: """
        ```mermaid
        flowchart LR
          A[Client] -->|request| B[Server]
        ```
        """
      )

    diagram = html |> LazyHTML.from_fragment() |> LazyHTML.query(~s([data-part="mermaid"]))

    assert LazyHTML.attribute(diagram, "phx-hook") == ["MermaidDiagram"]
    assert LazyHTML.attribute(diagram, "phx-update") == ["ignore"]
    assert [id] = LazyHTML.attribute(diagram, "id")
    assert String.starts_with?(id, "body-mermaid-1-")

    assert diagram |> LazyHTML.query(~s([data-part="mermaid-source"])) |> LazyHTML.text() ==
             "flowchart LR\n  A[Client] -->|request| B[Server]\n"
  end

  test "changes the diagram id when its source changes" do
    ids =
      for source <- ["flowchart LR\n  A --> B", "flowchart LR\n  A --> C"] do
        [id] =
          (&Markdown.content/1)
          |> render_component(id: "body", body: "```mermaid\n#{source}\n```")
          |> LazyHTML.from_fragment()
          |> LazyHTML.query(~s([data-part="mermaid"]))
          |> LazyHTML.attribute("id")

        id
      end

    assert Enum.uniq(ids) == ids
  end

  test "keeps other code blocks highlighted" do
    html = render_component(&Markdown.content/1, id: "body", body: "```elixir\n:ok\n```")

    assert html =~ "atlas-codeblock"
    refute html =~ "MermaidDiagram"
  end
end
