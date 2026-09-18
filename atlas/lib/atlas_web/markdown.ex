defmodule AtlasWeb.Markdown do
  @moduledoc false

  use Phoenix.Component
  use Noora

  import Phoenix.HTML

  @paragraph_wrap ~r/\A<p>(.*)<\/p>\z/s
  @tag_split ~r/(<[^>]+>)/
  @mention ~r/(^|[^A-Za-z0-9_\/])@([A-Za-z0-9](?:[A-Za-z0-9._-]{0,37}[A-Za-z0-9])?)/u
  @mention_skip_tags ~w(a code pre)

  @options [
    extension: [
      strikethrough: true,
      tagfilter: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true,
      shortcodes: true,
      alerts: true
    ],
    parse: [smart: true, relaxed_autolinks: true],
    render: [unsafe: false, hardbreaks: false],
    syntax_highlight: [
      formatter:
        {:html_inline, theme: "github_light", pre_class: "atlas-codeblock", italic: true, include_highlights: true}
    ],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  @alert_statuses %{
    note: "information",
    tip: "success",
    important: "information",
    warning: "warning",
    caution: "error"
  }

  attr :id, :string, required: true
  attr :body, :string, required: true
  attr :heading_offset, :integer, default: 1
  attr :strip_leading_h1, :boolean, default: false
  attr :rest, :global

  def content(assigns) do
    assigns =
      assign(assigns, :blocks,
        component_blocks(assigns.body, assigns.id,
          heading_offset: assigns.heading_offset,
          strip_leading_h1: assigns.strip_leading_h1
        )
      )

    ~H"""
    <div id={@id} class="markdown" {@rest}>
      <.markdown_block :for={block <- @blocks} block={block} />
    </div>
    """
  end

  attr :block, :any, required: true

  defp markdown_block(%{block: {:html, html}} = assigns) do
    assigns = assign(assigns, :html, html)

    ~H"""
    {@html}
    """
  end

  defp markdown_block(%{block: {:alert, status, title, description}} = assigns) do
    assigns =
      assign(assigns,
        status: status,
        title: title,
        description: description
      )

    ~H"""
    <.alert status={@status} type="secondary" size="large" title={@title}>
      {@description}
    </.alert>
    """
  end

  defp markdown_block(%{block: {:table, table}} = assigns) do
    assigns = assign(assigns, :table, table)

    ~H"""
    <.table id={@table.id} rows={@table.rows}>
      <:col
        :let={row}
        :for={{heading, column_index} <- Enum.with_index(@table.headings)}
        label={heading}
      >
        {Enum.at(row.cells, column_index)}
      </:col>
    </.table>
    """
  end

  def render(markdown) when is_binary(markdown) do
    markdown
    |> markdown_document()
    |> MDEx.to_html!(@options)
    |> highlight_mentions()
    |> raw()
  end

  def render(_markdown), do: raw("")

  def inline(text) when is_binary(text) do
    text
    |> MDEx.to_html!(@options)
    |> strip_paragraph_wrap()
    |> highlight_mentions()
    |> raw()
  end

  def inline(_text), do: raw("")

  def to_plain_text(text) when is_binary(text) do
    text
    |> decode_html_entities()
    |> strip_html()
    |> String.replace(~r/```[\s\S]*?```/, " ")
    |> String.replace(~r/~~~[\s\S]*?~~~/, " ")
    |> String.replace(~r/!\[[^\]]*\]\([^)]*\)/, " ")
    |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/^[ \t]*>+ ?/m, "")
    |> String.replace(~r/^[ \t]*[#]{1,6}[ \t]+/m, "")
    |> String.replace(~r/^[ \t]*(?:[-*+]|\d+\.)[ \t]+/m, "")
    |> String.replace(~r/`+/, "")
    |> String.replace(~r/\*+|~~/, "")
  end

  def to_plain_text(_text), do: ""

  def preview(text, limit \\ 180)

  def preview(text, limit) when is_binary(text) and is_integer(limit) and limit > 0 do
    text
    |> to_plain_text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, limit)
  end

  def preview(_text, _limit), do: ""

  defp component_blocks(markdown, id, opts) when is_binary(markdown) do
    document = markdown_document(markdown, opts)

    document.nodes
    |> maybe_strip_leading_h1(Keyword.get(opts, :strip_leading_h1, false))
    |> Enum.with_index()
    |> Enum.map(fn {node, index} -> component_block(node, document, id, index) end)
  end

  defp component_blocks(_markdown, _id, _opts), do: []

  defp maybe_strip_leading_h1([%MDEx.Heading{level: 1} | rest], true), do: rest
  defp maybe_strip_leading_h1(nodes, _strip?), do: nodes

  defp component_block(%MDEx.Alert{} = alert, document, _id, _index) do
    status = Map.fetch!(@alert_statuses, alert.alert_type)
    title = alert.alert_type |> Atom.to_string() |> String.capitalize()

    {:alert, status, title, render_nodes(document, alert.nodes)}
  end

  defp component_block(%MDEx.Table{} = table, document, id, index) do
    [header | rows] = table.nodes
    table_id = "#{id}-table-#{index + 1}"

    headings =
      Enum.map(header.nodes, fn cell ->
        cell.nodes
        |> Enum.map_join(&node_text/1)
        |> String.trim()
      end)

    rows =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, row_index} ->
        %{
          id: "#{table_id}-row-#{row_index}",
          cells: Enum.map(row.nodes, &render_nodes(document, &1.nodes))
        }
      end)

    {:table, %{id: table_id, headings: headings, rows: rows}}
  end

  defp component_block(node, document, _id, _index) do
    {:html, render_nodes(document, [node])}
  end

  defp markdown_document(markdown, opts \\ []) do
    offset = Keyword.get(opts, :heading_offset, 1)

    markdown
    |> MDEx.parse_document!(@options)
    |> MDEx.traverse_and_update(&shift_heading(&1, offset))
  end

  defp render_nodes(document, nodes) do
    document
    |> Map.put(:nodes, nodes)
    |> MDEx.to_html!(@options)
    |> highlight_mentions()
    |> raw()
  end

  defp node_text(%{literal: literal}) when is_binary(literal), do: literal
  defp node_text(%{nodes: nodes}) when is_list(nodes), do: Enum.map_join(nodes, &node_text/1)
  defp node_text(_node), do: ""

  defp shift_heading(%MDEx.Heading{level: level} = node, offset) when is_integer(offset) do
    %{node | level: level |> Kernel.+(offset) |> max(1) |> min(6)}
  end

  defp shift_heading(node, _offset), do: node

  defp strip_paragraph_wrap(html) do
    trimmed = String.trim(html)

    case Regex.run(@paragraph_wrap, trimmed, capture: :all_but_first) do
      [inner] -> inner
      _ -> trimmed
    end
  end

  defp strip_html(text) do
    text
    |> strip_tag_contents("script")
    |> strip_tag_contents("style")
    |> strip_tag_contents("noscript")
    |> String.replace(~r/<li\b[^>]*>/i, "\n")
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(
      ~r/<\/(p|div|section|article|aside|header|footer|nav|tr|table|ul|ol|h[1-6]|li)>/i,
      "\n"
    )
    |> String.replace(~r/<img\b[^>]*\balt=(["'])(.*?)\1[^>]*>/i, " \\2 ")
    |> String.replace(~r/<\/?[A-Za-z][^>]*>/, "")
    |> String.replace(~r/<!--.*?-->/s, " ")
  end

  defp strip_tag_contents(text, tag) do
    Regex.replace(~r/<#{tag}\b[^>]*>.*?<\/#{tag}>/is, text, "")
  end

  defp decode_html_entities(text) do
    text
    |> decode_numeric_entities(~r/&#(\d+);/, 10)
    |> decode_numeric_entities(~r/&#x([0-9a-fA-F]+);/, 16)
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&apos;", "'")
  end

  defp decode_numeric_entities(text, regex, base) do
    Regex.replace(regex, text, fn _match, codepoint ->
      codepoint
      |> String.to_integer(base)
      |> maybe_codepoint()
    end)
  end

  defp maybe_codepoint(codepoint) when codepoint in 0..0x10FFFF do
    <<codepoint::utf8>>
  rescue
    ArgumentError -> ""
  end

  defp maybe_codepoint(_codepoint), do: ""

  defp highlight_mentions(html) do
    @tag_split
    |> Regex.split(html, include_captures: true, trim: false)
    |> Enum.map_reduce([], &highlight_mentions_part/2)
    |> elem(0)
    |> Enum.join()
  end

  defp highlight_mentions_part("<" <> _rest = tag, skip_stack) do
    {tag, update_mention_skip_stack(skip_stack, tag)}
  end

  defp highlight_mentions_part(text, []), do: {highlight_mentions_text(text), []}
  defp highlight_mentions_part(text, skip_stack), do: {text, skip_stack}

  defp highlight_mentions_text(text) do
    Regex.replace(@mention, text, fn _match, prefix, handle ->
      mention = "@#{handle}"

      ~s(#{prefix}<span data-part="mention" data-mention="#{mention}">#{mention}</span>)
    end)
  end

  defp update_mention_skip_stack(skip_stack, tag) do
    cond do
      closing_tag = closing_tag_name(tag) ->
        List.delete(skip_stack, closing_tag)

      opening_tag = opening_tag_name(tag) ->
        if opening_tag in @mention_skip_tags and not self_closing_tag?(tag) do
          [opening_tag | skip_stack]
        else
          skip_stack
        end

      true ->
        skip_stack
    end
  end

  defp opening_tag_name(tag) do
    case Regex.run(~r/^<\s*([a-zA-Z0-9]+)/, tag, capture: :all_but_first) do
      [name] -> String.downcase(name)
      _ -> nil
    end
  end

  defp closing_tag_name(tag) do
    case Regex.run(~r/^<\s*\/\s*([a-zA-Z0-9]+)/, tag, capture: :all_but_first) do
      [name] -> String.downcase(name)
      _ -> nil
    end
  end

  defp self_closing_tag?(tag), do: String.match?(tag, ~r/\/\s*>\z/)
end
