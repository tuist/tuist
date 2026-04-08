defmodule Tuist.Docs.Loader do
  @moduledoc false

  use Noora

  import TuistWeb.Docs.MarkdownComponents

  alias Phoenix.HTML.Safe
  alias Tuist.Docs.HTML
  alias Tuist.Docs.Page
  alias Tuist.Locale

  # Live doc pages reference these modules from HEEx templates at compile time.
  require Noora.Alert

  # Paths
  @docs_root Path.expand("../../priv/docs", __DIR__)
  @locales Locale.supported_locales()
  @examples_root Path.expand("../../../examples/xcode", __DIR__)

  # Icons (rendered from Noora components at compile time)
  @copy_icon %{__changed__: nil} |> Noora.Icon.copy() |> Safe.to_iodata() |> IO.iodata_to_binary()
  @copy_check_icon %{__changed__: nil}
                   |> Noora.Icon.copy_check()
                   |> Safe.to_iodata()
                   |> IO.iodata_to_binary()

  # Regexes
  @frontmatter_regex ~r/\A---\s*\n(?<frontmatter>.*?)\n---\s*\n(?<body>.*)\z/s
  @localized_link_regex ~r/<LocalizedLink\s+(?:href|to)="([^"]+)"\s*>(.*?)<\/LocalizedLink>/s
  @script_setup_regex ~r/<script\s+setup>.*?<\/script>\s*/s
  @custom_heading_id_regex ~r/^(\#{1,6}\s+.*?)\s+\{#([\w-]+)\}\s*$/m
  @heading_extract_regex ~r/^(\#{2,4})\s+(.+?)(?:\s+\{#([\w-]+)\})?\s*$/m
  @code_group_regex ~r/^:::[ \t]*code-group[ \t]*\n(.*?)^:::[ \t]*$/ms
  @code_group_block_regex ~r/```(\w+)\s+\[([^\]]+)\]\n(.*?)```/s
  @bold_title_regex ~r/\A\s*<p><strong>([^<]+)<\/strong><\/p>\s*/s
  @code_content_regex ~r/(<code[^>]*>)(.*?)(<\/code>)/s

  @github_alert_type_to_status %{
    "note" => "information",
    "tip" => "success",
    "important" => "information",
    "warning" => "warning",
    "caution" => "error"
  }

  @mdex_options [
    extension: [
      header_ids: "",
      autolink: true,
      table: true,
      strikethrough: true,
      tasklist: true,
      alerts: true,
      phoenix_heex: true
    ],
    render: [unsafe: true],
    syntax_highlight: [formatter: {:html_inline, theme: "github_light"}]
  ]

  def load_pages! do
    source_paths =
      @locales
      |> Enum.flat_map(fn locale ->
        @docs_root
        |> Path.join(locale)
        |> Path.join("**/*.md")
        |> Path.wildcard()
      end)
      |> Enum.sort()
      |> Enum.reject(&excluded_source?/1)

    example_readmes =
      @examples_root
      |> Path.join("*/README.md")
      |> Path.wildcard()
      |> Enum.sort()

    pages = Enum.map(source_paths, &build_page!/1) ++ Enum.map(example_readmes, &build_example_page!/1)
    all_source_paths = source_paths ++ example_readmes
    {pages, all_source_paths}
  end

  def load_example_items! do
    @examples_root
    |> Path.join("*/README.md")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn readme_path ->
      dir_name = readme_path |> Path.dirname() |> Path.basename()
      markdown = File.read!(readme_path)
      title = title_from_markdown(markdown) || dir_name
      slug = "/en/references/examples/generated-projects/#{String.downcase(dir_name)}"
      {title, slug}
    end)
  end

  defp build_page!(source_path) do
    relative_path = Path.relative_to(source_path, @docs_root)
    slug = source_to_slug(relative_path)
    locale = relative_path |> String.split("/") |> List.first()
    contents = File.read!(source_path)

    {attrs, markdown} = parse_frontmatter(contents)
    {html, template, code_blocks} = render_markdown(markdown, source_path, locale, true)

    %Page{
      slug: slug,
      title: attrs["title"] || title_from_markdown(markdown) || slug,
      title_template: attrs["titleTemplate"],
      description: attrs["description"],
      body: html,
      body_template: template,
      code_blocks: code_blocks,
      markdown: markdown,
      source_path: relative_path,
      headings: extract_headings(markdown),
      last_modified: file_last_modified(source_path)
    }
  end

  defp build_example_page!(readme_path) do
    dir_name = readme_path |> Path.dirname() |> Path.basename()
    slug = "/en/references/examples/generated-projects/#{String.downcase(dir_name)}"
    markdown = File.read!(readme_path)
    title = title_from_markdown(markdown) || dir_name
    github_url = "https://github.com/tuist/tuist/tree/main/examples/xcode/#{dir_name}"

    markdown_with_link = markdown <> "\n\n[Check out example](#{github_url})\n"
    {html, template, code_blocks} = render_markdown(markdown_with_link, readme_path, "en", true)

    %Page{
      slug: slug,
      title: title,
      title_template: ":title · Examples · References · Tuist",
      description: "Example: #{title}",
      body: html,
      body_template: template,
      code_blocks: code_blocks,
      markdown: markdown_with_link,
      source_path: readme_path,
      headings: extract_headings(markdown_with_link),
      last_modified: file_last_modified(readme_path)
    }
  end

  defp render_markdown(markdown, source_path, locale, _live?) do
    custom_ids = extract_custom_heading_ids(markdown)

    processed_markdown =
      markdown
      |> String.replace(@script_setup_regex, "")
      |> localize_link_components(locale)
      |> strip_custom_heading_ids()
      |> convert_code_groups()

    html =
      [markdown: processed_markdown]
      |> MDEx.new()
      |> MDExMermaid.attach(mermaid_init: "")
      |> MDEx.Document.put_options(@mdex_options)
      |> MDEx.to_html!()
      |> convert_github_alerts()
      |> HTML.wrap_code_blocks()
      |> wrap_tables()
      |> strip_unsupported_tags()
      |> rewrite_image_paths()
      |> replace_heading_ids(custom_ids)
      |> HTML.add_heading_anchors()

    {safe_html, code_blocks} = extract_code_contents(html)
    safe_html = escape_heex_expressions(safe_html)

    case compile_heex_template(safe_html, source_path) do
      {:ok, template} -> {html, template, code_blocks}
      :error -> {html, nil, []}
    end
  end

  defp compile_heex_template(html, path) do
    {:ok,
     EEx.compile_string(
       html,
       engine: Phoenix.LiveView.TagEngine,
       file: path,
       line: 1,
       caller: __ENV__,
       indentation: 0,
       source: html,
       tag_handler: Phoenix.LiveView.HTMLEngine
     )}
  rescue
    _ -> :error
  end

  defp extract_code_contents(html) do
    blocks = @code_content_regex |> Regex.scan(html) |> Enum.map(fn [_, _, content, _] -> content end)

    {safe_html, _} =
      @code_content_regex
      |> Regex.scan(html, return: :index)
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.reduce({html, nil}, fn {[_full_idx, _open_idx, content_idx, _close_idx], idx}, {acc, _} ->
        {content_start, content_len} = content_idx
        placeholder = "<%= raw(Enum.at(@_doc_code_blocks, #{idx})) %>"
        acc = binary_replace_range(acc, content_start, content_len, placeholder)
        {acc, nil}
      end)

    {safe_html, blocks}
  end

  defp binary_replace_range(binary, start, len, replacement) do
    before = binary_part(binary, 0, start)
    after_part = binary_part(binary, start + len, byte_size(binary) - start - len)
    before <> replacement <> after_part
  end

  defp escape_heex_expressions(html) do
    parts = Regex.split(~r/(<%.*?%>|\{@\w+\})/s, html, include_captures: true)

    Enum.map_join(parts, fn part ->
      if String.starts_with?(part, "<%") or String.starts_with?(part, "{@"),
        do: part,
        else: String.replace(part, "{", "&#123;")
    end)
  end

  @alert_opening_regex ~r/<div class="markdown-alert markdown-alert-(\w+)">\s*<p class="markdown-alert-title">([^<]*)<\/p>\s*/s

  defp convert_github_alerts(html) do
    case Regex.run(@alert_opening_regex, html, return: :index) do
      nil ->
        html

      [{full_start, full_len}, {_, _} = type_idx, {_, _} = title_idx] ->
        type = binary_part(html, elem(type_idx, 0), elem(type_idx, 1))
        default_title = binary_part(html, elem(title_idx, 0), elem(title_idx, 1))
        after_header = full_start + full_len
        rest = binary_part(html, after_header, byte_size(html) - after_header)

        # Find the matching </div> by tracking depth (the alert's own <div> is already open)
        close_offset = find_matching_close_div(rest, 0, 1)
        content = binary_part(rest, 0, close_offset)
        after_alert = after_header + close_offset + byte_size("</div>")

        status = Map.get(@github_alert_type_to_status, type, "information")

        {title, content} =
          case Regex.run(@bold_title_regex, content) do
            [match, bold] -> {bold, String.replace_prefix(content, match, "")}
            _ -> {default_title, content}
          end

        title = title |> String.replace("\"", "&quot;") |> String.replace("<", "&lt;")

        replacement =
          ~s(<Noora.Alert.alert status="#{status}" title="#{title}" type="secondary" size="large">#{content}</Noora.Alert.alert>)

        before = binary_part(html, 0, full_start)
        after_part = binary_part(html, after_alert, byte_size(html) - after_alert)

        convert_github_alerts(before <> replacement <> after_part)
    end
  end

  defp find_matching_close_div(html, pos, depth) when depth > 0 do
    remaining = binary_part(html, pos, byte_size(html) - pos)
    open_match = :binary.match(remaining, "<div")
    close_match = :binary.match(remaining, "</div>")

    case {open_match, close_match} do
      {_, :nomatch} ->
        pos

      {{open_off, _}, {close_off, _}} when open_off < close_off ->
        find_matching_close_div(html, pos + open_off + 4, depth + 1)

      {_, {close_off, _}} ->
        if depth == 1, do: pos + close_off, else: find_matching_close_div(html, pos + close_off + 6, depth - 1)
    end
  end

  defp strip_unsupported_tags(html) do
    html
    |> String.replace(~r/<Badge[^>]*\/?>/, "")
    |> String.replace(~r/<\/Badge>/, "")
    |> String.replace(~r/<HomeCards[^>]*>.*?<\/HomeCards>/s, "")
    |> String.replace(~r/<HomeVideos[^>]*\/>/, "")
    |> String.replace(~r/<HomeCommunity[^>]*>.*?<\/HomeCommunity>/s, "")
  end

  defp wrap_tables(html) do
    html
    |> String.replace("<table>", ~s(<div class="noora-table"><table>))
    |> String.replace("</table>", "</table></div>")
  end

  defp rewrite_image_paths(html) do
    html
    |> String.replace(~s(src="/images/), ~s(src="/docs/images/))
    |> String.replace(~s(src="/logo.png"), ~s(src="/docs/images/logo.webp"))
  end

  defp localize_link_components(markdown, _locale) do
    Regex.replace(@localized_link_regex, markdown, fn _, href, text ->
      ~s(<.localized_link href="#{href}" locale={@locale}>#{text}</.localized_link>)
    end)
  end

  defp convert_code_groups(markdown) do
    Regex.replace(@code_group_regex, markdown, fn _, content ->
      convert_code_group(content)
    end)
  end

  defp convert_code_group(content) do
    tabs = Regex.scan(@code_group_block_regex, content)

    if tabs == [] do
      String.trim(content)
    else
      tab_buttons =
        tabs
        |> Enum.with_index()
        |> Enum.map_join("", fn {[_, _lang, label, _code], index} ->
          selected = if index == 0, do: ~s( data-selected="true"), else: ""

          EEx.eval_string(
            ~s(<button data-part="tab" data-index="<%= index %>"<%= selected %>><%= label %></button>),
            index: index,
            selected: selected,
            label: label
          )
        end)

      tab_panels =
        tabs
        |> Enum.with_index()
        |> Enum.map_join("", fn {[_, lang, _label, code], index} ->
          hidden = if index == 0, do: "", else: ~s( data-hidden="true")

          EEx.eval_string(
            ~s(<div data-part="panel" data-index="<%= index %>"<%= hidden %>>\n\n```<%= lang %>\n<%= code %>```\n\n</div>),
            index: index,
            hidden: hidden,
            lang: lang,
            code: code
          )
        end)

      copy_button =
        EEx.eval_string(
          ~s(<button data-part="copy" aria-label="Copy code"><span data-part="copy-icon"><%= copy_icon %></span><span data-part="copy-check-icon"><%= copy_check_icon %></span></button>),
          copy_icon: @copy_icon,
          copy_check_icon: @copy_check_icon
        )

      EEx.eval_string(
        ~s(<div class="code-group"><div data-part="header"><div data-part="tabs"><%= tab_buttons %></div><%= copy_button %></div><div data-part="panels"><%= tab_panels %></div></div>\n),
        tab_buttons: tab_buttons,
        copy_button: copy_button,
        tab_panels: tab_panels
      )
    end
  end

  defp strip_custom_heading_ids(markdown) do
    Regex.replace(@custom_heading_id_regex, markdown, "\\1")
  end

  defp extract_custom_heading_ids(markdown) do
    cleaned = String.replace(markdown, @script_setup_regex, "")

    @custom_heading_id_regex
    |> Regex.scan(cleaned)
    |> Map.new(fn [_, heading_text, custom_id] ->
      text =
        heading_text
        |> String.replace(~r/^[#]{1,6}\s+/, "")
        |> strip_html()

      auto_id =
        text
        |> String.downcase()
        |> String.replace(~r/[^\w\s-]/u, "")
        |> String.replace(~r/\s+/, "-")
        |> String.trim("-")

      {auto_id, custom_id}
    end)
  end

  defp replace_heading_ids(html, custom_ids) when map_size(custom_ids) == 0, do: html

  defp replace_heading_ids(html, custom_ids) do
    Enum.reduce(custom_ids, html, fn {auto_id, custom_id}, acc ->
      if auto_id == custom_id do
        acc
      else
        acc
        |> String.replace(~s(id="#{auto_id}"), ~s(id="#{custom_id}"))
        |> String.replace(~s(href="##{auto_id}"), ~s(href="##{custom_id}"))
      end
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

  defp excluded_source?(source_path) do
    relative_path = Path.relative_to(source_path, @docs_root)

    String.contains?(relative_path, "[") or
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

  defp file_last_modified(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} ->
        mtime
        |> NaiveDateTime.from_erl!()
        |> NaiveDateTime.to_date()

      _ ->
        nil
    end
  end

  defp title_from_markdown(markdown) do
    case Regex.run(~r/^\s*#\s+(.+?)(?:\s+\{#.*\})?\s*$/m, markdown, capture: :all_but_first) do
      [title] -> String.trim(title)
      _ -> nil
    end
  end

  defp strip_html(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end
end
