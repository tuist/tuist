defmodule TuistWeb.Utilities.HtmlToMarkdown do
  @moduledoc false

  alias HtmlToMarkdown.Options

  @content_root_selectors ["main", "[role='main']", "article", "body"]
  @conversion_options %Options{
    code_block_style: :backticks,
    extract_metadata: false,
    heading_style: :atx
  }

  def convert(html, opts \\ []) when is_binary(html) do
    request_url = Keyword.get(opts, :request_url)

    case Floki.parse_document(html) do
      {:ok, document} ->
        title = extract_title(document)

        markdown =
          document
          |> content_root()
          |> absolutize_urls(base_uri(request_url))
          |> Floki.raw_html()
          |> HtmlToMarkdown.convert!(@conversion_options)
          |> cleanup_markdown()
          |> maybe_prepend_title(title)

        if markdown == "", do: title, else: markdown

      {:error, _reason} ->
        html
    end
  end

  defp content_root(document) do
    Enum.find_value(@content_root_selectors, document, fn selector ->
      case Floki.find(document, selector) do
        [node | _] -> [node]
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

  defp cleanup_markdown(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.trim()
  end

  defp maybe_prepend_title(markdown, title) when title in [nil, ""], do: markdown
  defp maybe_prepend_title("", title), do: "# " <> title

  defp maybe_prepend_title(markdown, title) do
    if starts_with_heading?(markdown, title) do
      markdown
    else
      "# " <> title <> "\n\n" <> markdown
    end
  end

  defp starts_with_heading?(markdown, title) do
    markdown
    |> String.split("\n", parts: 2)
    |> List.first()
    |> normalize_heading()
    |> Kernel.==(title)
  end

  defp normalize_heading(nil), do: ""

  defp normalize_heading(line) do
    line
    |> String.trim()
    |> String.trim_leading("#")
    |> normalize_text()
  end

  defp normalize_text(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
