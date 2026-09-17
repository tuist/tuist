defmodule Atlas.Support.Markdown do
  @moduledoc false

  @mdex_options [
    extension: [autolink: true],
    render: [hardbreaks: true],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  def to_html(markdown) when is_binary(markdown), do: MDEx.to_html!(markdown, @mdex_options)

  def to_text(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.parse_document!(@mdex_options)
    |> block_nodes_to_text()
    |> String.trim()
  end

  defp block_nodes_to_text(%{nodes: nodes}) do
    nodes
    |> Enum.map(&block_to_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp block_to_text(%MDEx.List{} = list) do
    list.nodes
    |> Enum.with_index(list.start)
    |> Enum.map_join("\n", fn {item, index} ->
      prefix = if list.list_type == :ordered, do: "#{index}. ", else: "- "
      prefix <> item_to_text(item)
    end)
  end

  defp block_to_text(%MDEx.CodeBlock{literal: literal}), do: literal
  defp block_to_text(%MDEx.ThematicBreak{}), do: ""
  defp block_to_text(%MDEx.HtmlBlock{}), do: ""
  defp block_to_text(node), do: inline_to_text(node)

  defp item_to_text(%{nodes: nodes}), do: nodes |> Enum.map_join("\n", &block_to_text/1)
  defp item_to_text(node), do: inline_to_text(node)

  defp inline_to_text(%MDEx.Text{literal: literal}), do: literal
  defp inline_to_text(%MDEx.Code{literal: literal}), do: literal
  defp inline_to_text(%MDEx.Math{literal: literal}), do: literal
  defp inline_to_text(%MDEx.ShortCode{emoji: emoji}), do: emoji
  defp inline_to_text(%MDEx.SoftBreak{}), do: "\n"
  defp inline_to_text(%MDEx.LineBreak{}), do: "\n"
  defp inline_to_text(%MDEx.HtmlInline{}), do: ""

  defp inline_to_text(%MDEx.Link{nodes: nodes, url: url}) do
    link_text = inline_nodes_to_text(nodes)
    if link_text == url, do: link_text, else: "#{link_text}: #{url}"
  end

  defp inline_to_text(%MDEx.Image{nodes: nodes, url: url}) do
    alt_text = inline_nodes_to_text(nodes)
    if alt_text == "", do: url, else: "#{alt_text}: #{url}"
  end

  defp inline_to_text(%{literal: literal}) when is_binary(literal), do: literal
  defp inline_to_text(%{nodes: nodes}), do: inline_nodes_to_text(nodes)
  defp inline_to_text(_node), do: ""

  defp inline_nodes_to_text(nodes), do: Enum.map_join(nodes, "", &inline_to_text/1)
end
