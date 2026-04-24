defmodule TuistWeb.Utilities.HtmlToMarkdown do
  @moduledoc false

  @content_root_selectors ["main", "[role='main']", "article", "body"]
  @heading_tags ~w(h1 h2 h3 h4 h5 h6)
  @conversion_options %{
    markdown_flavor: :basic,
    normalize_whitespace: true
  }

  def convert(html, opts \\ []) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> document_to_markdown(Keyword.get(opts, :request_url))
        |> fallback_to_title(extract_title(document))

      {:error, _reason} ->
        html
    end
  end

  defp document_to_markdown(document, request_url) do
    title = extract_title(document)

    document
    |> content_root()
    |> maybe_insert_title_heading(title)
    |> absolutize_urls(base_uri(request_url))
    |> Floki.raw_html()
    |> Html2Markdown.convert(@conversion_options)
    |> String.trim()
  end

  defp content_root(document) do
    Enum.find_value(@content_root_selectors, document, fn selector ->
      case Floki.find(document, selector) do
        [{_tag, _attrs, children} | _] -> children
        [] -> nil
      end
    end)
  end

  defp extract_title(document) do
    document
    |> Floki.find("title")
    |> Floki.text()
    |> normalize_text()
  end

  defp base_uri(nil), do: nil
  defp base_uri(request_url), do: URI.parse(request_url)

  defp absolutize_urls(nodes, nil), do: nodes

  defp absolutize_urls(nodes, base_uri) when is_list(nodes) do
    Enum.map(nodes, &absolutize_urls(&1, base_uri))
  end

  defp absolutize_urls(text, _base_uri) when is_binary(text), do: text

  defp absolutize_urls({tag, attrs, children}, base_uri) do
    normalized_attrs =
      Enum.map(attrs, fn
        {"href", value} -> {"href", maybe_absolute_url(value, base_uri)}
        {"src", value} -> {"src", maybe_absolute_url(value, base_uri)}
        {"poster", value} -> {"poster", maybe_absolute_url(value, base_uri)}
        attr -> attr
      end)

    {tag, normalized_attrs, absolutize_urls(children, base_uri)}
  end

  defp maybe_absolute_url(nil, _base_uri), do: nil
  defp maybe_absolute_url("", _base_uri), do: ""

  defp maybe_absolute_url(value, base_uri) do
    uri = URI.parse(value)

    cond do
      uri.scheme not in [nil, ""] ->
        value

      uri.host not in [nil, ""] ->
        URI.to_string(%{uri | scheme: base_uri.scheme})

      true ->
        base_uri
        |> URI.merge(value)
        |> URI.to_string()
    end
  rescue
    ArgumentError -> value
  end

  defp maybe_insert_title_heading(nodes, title) when title in [nil, ""], do: nodes

  defp maybe_insert_title_heading(nodes, title) do
    if first_heading_matches_title?(nodes, title) do
      nodes
    else
      prepend_title_heading(nodes, title)
    end
  end

  defp prepend_title_heading(nodes, title) do
    [title_heading(title) | nodes]
  end

  defp title_heading(title), do: {"h1", [], [title]}

  defp fallback_to_title(markdown, title) when markdown == "" and title not in [nil, ""], do: title
  defp fallback_to_title(markdown, _title), do: markdown

  defp first_heading_matches_title?(nodes, title) do
    case first_content_node(nodes) do
      {tag, _attrs, children} when tag in @heading_tags ->
        heading_text(children) == title

      _ ->
        false
    end
  end

  defp first_content_node(nodes) when is_list(nodes) do
    Enum.find(nodes, &content_node?/1)
  end

  defp content_node?({:comment, _}), do: false
  defp content_node?(text) when is_binary(text), do: String.trim(text) != ""
  defp content_node?({_tag, _attrs, _children}), do: true
  defp content_node?(_node), do: false

  defp heading_text(children) do
    children
    |> Floki.text()
    |> normalize_text()
  end

  defp normalize_text(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
