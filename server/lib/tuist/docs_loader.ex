defmodule Tuist.Docs.Loader do
  @moduledoc false

  alias Tuist.Docs.Page

  @docs_root Path.expand("../../../docs/docs", __DIR__)
  @english_docs_root Path.join(@docs_root, "en")
  @frontmatter_regex ~r/\A---\s*\n(?<frontmatter>.*?)\n---\s*\n(?<body>.*)\z/s
  @localized_link_regex ~r/<LocalizedLink\s+href="([^"]+)"\s*>(.*?)<\/LocalizedLink>/s
  @script_setup_regex ~r/<script\s+setup>.*?<\/script>\s*/s
  @custom_heading_id_regex ~r/^(\#{1,6}\s+.*?)\s+\{#([\w-]+)\}\s*$/m
  @heading_extract_regex ~r/^(\#{2,4})\s+(.+?)(?:\s+\{#([\w-]+)\})?\s*$/m
  @vitepress_container_regex ~r/^:::\s*(\w+)\s*\n(.*?)^:::\s*$/ms

  def load_pages! do
    source_paths =
      @english_docs_root
      |> Path.join("**/*.md")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reject(&excluded_source?/1)

    pages = Enum.map(source_paths, &build_page!/1)
    {pages, source_paths}
  end

  defp build_page!(source_path) do
    relative_path = Path.relative_to(source_path, @docs_root)
    slug = source_to_slug(relative_path)
    contents = File.read!(source_path)

    {attrs, markdown} = parse_frontmatter(contents)
    headings = extract_headings(markdown)
    html = render_markdown(markdown)

    %Page{
      slug: slug,
      title: get_attr(attrs, "title") || title_from_markdown(markdown) || slug,
      description: get_attr(attrs, "description"),
      body: html,
      source_path: relative_path,
      headings: headings
    }
  end

  defp excluded_source?(source_path) do
    relative_path = Path.relative_to(source_path, @docs_root)

    String.contains?(relative_path, "[") or
      String.starts_with?(relative_path, "en/cli/") or
      String.starts_with?(relative_path, "en/references/project-description/")
  end

  defp source_to_slug(relative_path) do
    without_extension = String.trim_trailing(relative_path, ".md")
    segments = String.split(without_extension, "/", trim: true)

    slug_segments =
      case Enum.reverse(segments) do
        ["index" | rest] -> Enum.reverse(rest)
        _ -> segments
      end

    "/" <> Enum.join(slug_segments, "/")
  end

  defp parse_frontmatter(contents) do
    case Regex.named_captures(@frontmatter_regex, contents) do
      %{"frontmatter" => frontmatter, "body" => body} ->
        {parse_frontmatter_data(frontmatter), body}

      _ ->
        {%{}, contents}
    end
  end

  defp parse_frontmatter_data(frontmatter) do
    case YamlElixir.read_from_string(frontmatter) do
      {:ok, attrs} when is_map(attrs) ->
        attrs

      _ ->
        case Jason.decode(frontmatter) do
          {:ok, attrs} when is_map(attrs) -> attrs
          _ -> %{}
        end
    end
  end

  defp render_markdown(markdown) do
    markdown
    |> String.replace(@script_setup_regex, "")
    |> localize_link_components()
    |> strip_custom_heading_ids()
    |> convert_vitepress_containers()
    |> MDEx.to_html!(
      extension: [
        header_ids: "",
        autolink: true,
        table: true,
        strikethrough: true,
        tasklist: true,
        alerts: true
      ],
      render: [unsafe: true],
      syntax_highlight: [formatter: {:html_inline, theme: "onedark"}]
    )
  end

  defp localize_link_components(markdown) do
    Regex.replace(@localized_link_regex, markdown, fn _, href, text ->
      ~s(<a href="#{localize_href(href)}">#{text}</a>)
    end)
  end

  defp strip_custom_heading_ids(markdown) do
    Regex.replace(@custom_heading_id_regex, markdown, "\\1")
  end

  defp convert_vitepress_containers(markdown) do
    Regex.replace(@vitepress_container_regex, markdown, fn _, type, content ->
      ~s(<div class="docs-container docs-container--#{type}">\n\n#{String.trim(content)}\n\n</div>\n)
    end)
  end

  defp extract_headings(markdown) do
    cleaned = String.replace(markdown, @script_setup_regex, "")

    @heading_extract_regex
    |> Regex.scan(cleaned)
    |> Enum.map(fn
      [_, hashes, text, custom_id] when custom_id != "" ->
        %{level: String.length(hashes), text: strip_html(text), id: custom_id}

      [_, hashes, text | _] ->
        clean_text = strip_html(text)

        id =
          clean_text
          |> String.downcase()
          |> String.replace(~r/[^\w\s-]/u, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        %{level: String.length(hashes), text: clean_text, id: id}
    end)
  end

  defp strip_html(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end

  defp localize_href("/en/" <> _ = href), do: "/docs" <> href
  defp localize_href("/" <> _ = href), do: "/docs/en" <> href
  defp localize_href(href), do: href

  defp title_from_markdown(markdown) do
    case Regex.run(~r/^\s*#\s+(.+?)(?:\s+\{#.*\})?\s*$/m, markdown, capture: :all_but_first) do
      [title] -> String.trim(title)
      _ -> nil
    end
  end

  defp get_attr(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} ->
        value

      :error ->
        atom_key = existing_atom_key(key)

        if is_nil(atom_key), do: nil, else: Map.get(attrs, atom_key)
    end
  end

  defp existing_atom_key(key) when is_binary(key) do
    atom_key = String.to_existing_atom(key)
    atom_key
  rescue
    ArgumentError -> nil
  end
end
