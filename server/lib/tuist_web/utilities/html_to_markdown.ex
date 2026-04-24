defmodule TuistWeb.Utilities.HtmlToMarkdown do
  @moduledoc false

  @skipped_tags ~w(canvas nav noscript script style svg template)
  @relative_url_schemes ["http", "https"]

  def convert(html, opts \\ []) when is_binary(html) do
    request_url = Keyword.get(opts, :request_url)

    case Floki.parse_document(html) do
      {:ok, document} ->
        title = extract_title(document)

        markdown =
          document
          |> content_root()
          |> block_children_to_markdown(%{base_uri: base_uri(request_url), list_depth: 0})
          |> cleanup_markdown()
          |> maybe_prepend_title(title)

        if markdown == "" do
          title
        else
          markdown
        end

      {:error, _reason} ->
        html
    end
  end

  defp content_root(document) do
    Enum.find_value(["main", "[role='main']", "article", "body"], fn selector ->
      case Floki.find(document, selector) do
        [node | _] -> [node]
        [] -> nil
      end
    end) || []
  end

  defp extract_title(document) do
    document
    |> Floki.find("title")
    |> Floki.text()
    |> normalize_block_text()
  end

  defp base_uri(nil), do: nil
  defp base_uri(request_url), do: URI.parse(request_url)

  defp block_children_to_markdown(children, ctx) when is_list(children) do
    Enum.map_join(children, &block_node_to_markdown(&1, ctx))
  end

  defp block_node_to_markdown(text, _ctx) when is_binary(text) do
    case normalize_block_text(text) do
      "" -> ""
      normalized -> normalized <> "\n\n"
    end
  end

  defp block_node_to_markdown({tag, attrs, children}, ctx) do
    tag = String.downcase(tag)

    cond do
      skip_node?(tag, attrs) ->
        ""

      tag in ["body", "main", "article", "section", "div", "header", "aside"] ->
        block_children_to_markdown(children, ctx)

      tag in ["h1", "h2", "h3", "h4", "h5", "h6"] ->
        level = tag |> String.trim_leading("h") |> String.to_integer()
        heading = inline_children_to_markdown(children, ctx)

        if heading == "" do
          ""
        else
          String.duplicate("#", level) <> " " <> heading <> "\n\n"
        end

      tag == "p" ->
        paragraph(children, ctx)

      tag == "blockquote" ->
        blockquote(children, ctx)

      tag == "pre" ->
        code_block(children, ctx)

      tag == "ul" ->
        list(children, ctx, :unordered)

      tag == "ol" ->
        list(children, ctx, :ordered)

      tag == "table" ->
        table({tag, attrs, children}, ctx)

      tag == "hr" ->
        "---\n\n"

      tag == "figure" ->
        block_children_to_markdown(children, ctx)

      tag == "figcaption" ->
        case inline_children_to_markdown(children, ctx) do
          "" -> ""
          caption -> "_" <> caption <> "_\n\n"
        end

      tag in ["details", "summary"] ->
        paragraph(children, ctx)

      true ->
        paragraph(children, ctx)
    end
  end

  defp paragraph(children, ctx) do
    case inline_children_to_markdown(children, ctx) do
      "" -> ""
      text -> text <> "\n\n"
    end
  end

  defp blockquote(children, ctx) do
    quoted =
      children
      |> block_children_to_markdown(ctx)
      |> String.trim()

    if quoted == "" do
      ""
    else
      quoted
      |> String.split("\n")
      |> Enum.map_join("\n", &("> " <> &1))
      |> Kernel.<>("\n\n")
    end
  end

  defp code_block(children, ctx) do
    {language, code} = extract_code(children, ctx)

    if code == "" do
      ""
    else
      fence =
        case language do
          nil -> "```"
          value -> "```" <> value
        end

      fence <> "\n" <> code <> "\n```\n\n"
    end
  end

  defp extract_code([{"code", attrs, children}], _ctx) do
    {code_language(attrs), children |> raw_text() |> String.trim_trailing()}
  end

  defp extract_code(children, _ctx) do
    {nil, children |> raw_text() |> String.trim_trailing()}
  end

  defp code_language(attrs) do
    attrs
    |> attribute("class")
    |> case do
      nil ->
        nil

      class_value ->
        case Regex.run(~r/language-([\w+-]+)/, class_value, capture: :all_but_first) do
          [language] -> language
          _ -> nil
        end
    end
  end

  defp list(children, ctx, type) do
    items =
      children
      |> Enum.filter(&match?({"li", _, _}, &1))
      |> Enum.with_index(1)
      |> Enum.map(fn {{_tag, _attrs, item_children}, index} ->
        list_item(item_children, %{ctx | list_depth: ctx.list_depth + 1}, type, index)
      end)
      |> Enum.reject(&(&1 == ""))

    case items do
      [] -> ""
      _ -> Enum.join(items, "\n") <> "\n\n"
    end
  end

  defp list_item(children, ctx, type, index) do
    content =
      children
      |> Enum.map_join(&block_node_to_markdown(&1, ctx))
      |> String.trim()

    if content == "" do
      ""
    else
      indentation = String.duplicate("  ", ctx.list_depth - 1)
      prefix = if(type == :ordered, do: "#{index}. ", else: "- ")
      continuation = indentation <> String.duplicate(" ", String.length(prefix))

      content
      |> String.split("\n")
      |> Enum.with_index()
      |> Enum.map_join("\n", fn
        {line, 0} -> indentation <> prefix <> line
        {line, _line_index} -> continuation <> line
      end)
    end
  end

  defp table(table_node, ctx) do
    rows =
      table_node
      |> Floki.find("tr")
      |> Enum.map(fn row ->
        row
        |> Floki.find("th, td")
        |> Enum.map(&inline_children_to_markdown(element_children(&1), ctx))
      end)
      |> Enum.reject(&Enum.all?(&1, fn value -> value == "" end))

    case rows do
      [header | body] when header != [] ->
        separator = Enum.map_join(header, " | ", fn _ -> "---" end)

        [
          "| " <> Enum.join(header, " | ") <> " |",
          "| " <> separator <> " |"
          | Enum.map(body, fn row -> "| " <> Enum.join(row, " | ") <> " |" end)
        ]
        |> Enum.join("\n")
        |> Kernel.<>("\n\n")

      _ ->
        block_children_to_markdown(element_children(table_node), ctx)
    end
  end

  defp inline_children_to_markdown(children, ctx) when is_list(children) do
    children
    |> Enum.map_join(&inline_node_to_markdown(&1, ctx))
    |> cleanup_inline()
  end

  defp inline_node_to_markdown(text, _ctx) when is_binary(text) do
    normalize_inline_text(text)
  end

  defp inline_node_to_markdown({tag, attrs, children}, ctx) do
    tag = String.downcase(tag)

    cond do
      skip_node?(tag, attrs) ->
        ""

      tag == "br" ->
        "  \n"

      tag in ["strong", "b"] ->
        wrap_inline("**", children, ctx)

      tag in ["em", "i"] ->
        wrap_inline("*", children, ctx)

      tag == "code" ->
        case children |> raw_text() |> String.trim() do
          "" -> ""
          code -> "`" <> code <> "`"
        end

      tag == "a" ->
        link(children, attrs, ctx)

      tag == "img" ->
        image(attrs, ctx)

      tag == "iframe" ->
        embed_link("Embedded content", attrs, ctx)

      tag in ["video", "audio", "source"] ->
        embed_link("Media", attrs, ctx)

      tag in ["span", "small", "u", "sub", "sup", "time", "mark"] ->
        inline_children_to_markdown(children, ctx)

      tag in ["ul", "ol"] ->
        "\n" <> String.trim(list(children, ctx, if(tag == "ol", do: :ordered, else: :unordered))) <> "\n"

      tag == "p" ->
        inline_children_to_markdown(children, ctx)

      true ->
        inline_children_to_markdown(children, ctx)
    end
  end

  defp wrap_inline(wrapper, children, ctx) do
    case inline_children_to_markdown(children, ctx) do
      "" -> ""
      content -> wrapper <> content <> wrapper
    end
  end

  defp link(children, attrs, ctx) do
    label = inline_children_to_markdown(children, ctx)
    href = attrs |> attribute("href") |> resolve_url(ctx.base_uri)

    cond do
      href in [nil, "", "#"] ->
        label

      label == "" ->
        href

      true ->
        "[" <> label <> "](" <> href <> ")"
    end
  end

  defp image(attrs, ctx) do
    src = attrs |> attribute("src") |> resolve_url(ctx.base_uri)
    alt = attribute(attrs, "alt") || ""

    case src do
      nil -> alt
      value -> "![" <> alt <> "](" <> value <> ")"
    end
  end

  defp embed_link(label, attrs, ctx) do
    src =
      attrs
      |> attribute("src")
      |> resolve_url(ctx.base_uri)

    case src do
      nil -> ""
      value -> "[" <> label <> "](" <> value <> ")"
    end
  end

  defp cleanup_inline(markdown) do
    markdown
    |> String.replace(~r/\s+([,.;:!?])/, "\\1")
    |> String.replace(~r/\(\s+/, "(")
    |> String.replace(~r/\s+\)/, ")")
    |> String.replace(~r"[ \t]+\n", "\n")
    |> String.trim()
  end

  defp cleanup_markdown(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/[ \t]+\n/, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp maybe_prepend_title("", title), do: title
  defp maybe_prepend_title(markdown, ""), do: markdown

  defp maybe_prepend_title(markdown, title) do
    if String.match?(markdown, ~r/^\s*#\s+/) do
      markdown
    else
      "# " <> title <> "\n\n" <> markdown
    end
  end

  defp normalize_block_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_inline_text(text) do
    String.replace(text, ~r/\s+/, " ")
  end

  defp raw_text(children) when is_list(children) do
    Enum.map_join(children, "", &raw_text/1)
  end

  defp raw_text(text) when is_binary(text), do: text
  defp raw_text({_tag, _attrs, children}), do: raw_text(children)
  defp raw_text(_), do: ""

  defp resolve_url(nil, _base_uri), do: nil
  defp resolve_url("", _base_uri), do: nil
  defp resolve_url("#" = anchor, _base_uri), do: anchor
  defp resolve_url(url, nil), do: url

  defp resolve_url(url, base_uri) do
    case URI.parse(url) do
      %URI{scheme: nil, host: nil} ->
        base_uri |> URI.merge(url) |> URI.to_string()

      %URI{scheme: nil, host: host} when is_binary(host) ->
        base_scheme = if base_uri.scheme in @relative_url_schemes, do: base_uri.scheme, else: "https"
        base_scheme <> ":" <> url

      _ ->
        url
    end
  end

  defp skip_node?(tag, attrs) do
    tag in @skipped_tags or attribute(attrs, "hidden") != nil or attribute(attrs, "aria-hidden") == "true"
  end

  defp attribute(attrs, key) do
    Enum.find_value(attrs, fn
      {^key, value} -> value
      _ -> nil
    end)
  end

  defp element_children({_tag, _attrs, children}), do: children
end
