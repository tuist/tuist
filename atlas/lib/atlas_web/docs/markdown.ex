defmodule AtlasWeb.Docs.Markdown do
  @moduledoc false
  use Phoenix.Component
  use Noora

  import Phoenix.HTML

  alias Phoenix.HTML.Safe

  @options [
    extension: [table: true, autolink: true, alerts: true],
    render: [unsafe: false],
    sanitize: MDEx.Document.default_sanitize_options()
  ]
  @statuses %{note: "information", tip: "success", important: "information", warning: "warning", caution: "error"}

  def render(body), do: body |> render_with_headings() |> elem(0)

  def render_with_headings(body) do
    document = MDEx.parse_document!(body, @options)

    headings = heading_entries(document)

    html =
      document.nodes
      |> Enum.with_index()
      |> Enum.map_join(fn
        {%MDEx.Table{} = node, index} -> render_table(node, document, index)
        {node, _index} -> render_node(node, document)
      end)

    [prefix | sections] = String.split(html, "<h2>")

    if length(sections) != length(headings), do: raise("Documentation heading rendering disagrees with parsed headings")

    html =
      prefix <>
        Enum.map_join(Enum.zip(sections, headings), fn {section, heading} ->
          "<h2 id=\"#{heading.id}\">" <> section
        end)

    {html, headings}
  end

  defp heading_entries(document) do
    document
    |> Enum.filter(&match?(%MDEx.Heading{level: 2}, &1))
    |> Enum.map_reduce(MapSet.new(), fn heading, used ->
      title = plain_text(heading)
      base = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
      base = if base == "", do: "section", else: base

      id =
        Stream.iterate(1, &(&1 + 1))
        |> Enum.find_value(fn index ->
          candidate = if index == 1, do: base, else: "#{base}-#{index}"
          if !MapSet.member?(used, candidate), do: candidate
        end)

      {%{title: title, id: id}, MapSet.put(used, id)}
    end)
    |> elem(0)
  end

  defp plain_text(%MDEx.HtmlInline{}), do: ""
  defp plain_text(%{literal: literal}), do: literal
  defp plain_text(%{nodes: nodes}), do: Enum.map_join(nodes, &plain_text/1)
  defp plain_text(_node), do: " "

  defp render_table(node, document, index) do
    %{html: raw(render_nodes(document, [node])), index: index, __changed__: nil}
    |> markdown_table()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :html, :any, required: true
  attr :index, :integer, required: true

  defp markdown_table(assigns) do
    ~H"""
    <div
      id={"docs-markdown-table-#{@index}"}
      class="noora-table"
      data-part="docs-table"
      phx-hook="NooraTable"
      phx-update="ignore"
    >
      <div data-part="scroll-container">{@html}</div>
      <div data-part="scrollbar" aria-hidden="true">
        <div data-part="scrollbar-content"></div>
      </div>
      <div data-part="overlay-scrollbar" aria-hidden="true">
        <div data-part="overlay-thumb"></div>
      </div>
    </div>
    """
  end

  defp render_node(%MDEx.CodeBlock{literal: source, info: info}, _document) do
    language = info |> String.split() |> List.first() || "text"

    %{source: String.trim_trailing(source, "\n"), language: language, __changed__: nil}
    |> code_snippet()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp render_node(%MDEx.Alert{} = alert, document) do
    %{
      status: Map.fetch!(@statuses, alert.alert_type),
      title: alert.alert_type |> Atom.to_string() |> String.capitalize(),
      description: raw(render_nodes(document, alert.nodes)),
      __changed__: nil
    }
    |> admonition()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp render_node(node, document), do: render_nodes(document, [node])

  defp render_nodes(document, nodes), do: document |> Map.put(:nodes, nodes) |> MDEx.to_html!(@options)

  attr :source, :string, required: true
  attr :language, :string, required: true

  defp code_snippet(assigns) do
    ~H"""
    <div data-part="code-window">
      <div data-part="bar">
        <div data-part="language">{@language}</div>
        <.neutral_button data-part="copy" size="large" aria-label="Copy code">
          <span data-part="copy-icon"><.copy /></span>
          <span data-part="copy-check-icon"><.check /></span>
        </.neutral_button>
      </div>
      <template data-part="copy-source">{@source}</template>
      <div data-part="code"><pre><code>{@source}</code></pre></div>
    </div>
    """
  end

  attr :status, :string, required: true
  attr :title, :string, required: true
  attr :description, :any, required: true

  defp admonition(assigns) do
    ~H"""
    <.alert status={@status} type="secondary" size="large" title={@title} data-part="admonition">
      {@description}
    </.alert>
    """
  end
end
