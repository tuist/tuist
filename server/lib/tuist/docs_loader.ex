defmodule Tuist.Docs.Loader do
  @moduledoc false

  alias Tuist.Docs.HTML
  alias Tuist.Docs.Page
  alias Tuist.Docs.Paths

  # Paths
  @docs_root Path.expand("../../../docs/docs", __DIR__)
  @locales ~w(en ar es ja ko pl pt ru yue_Hant zh_Hans)
  @examples_root Path.expand("../../../examples/xcode", __DIR__)

  # Icons
  @noora_icons_path Path.expand("../noora/lib/noora/icons", File.cwd!())
  @copy_icon @noora_icons_path |> Path.join("copy.svg") |> File.read!() |> String.trim()
  @copy_check_icon @noora_icons_path |> Path.join("copy-check.svg") |> File.read!() |> String.trim()
  @alert_circle_icon ~s(<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0" /><path d="M12 8v4" /><path d="M12 16h.01" /></svg>)
  @circle_check_icon ~s(<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0 -18 0" /><path d="M9 12l2 2l4 -4" /></svg>)
  @alert_triangle_icon ~s(<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M12 9v4" /><path d="M10.363 3.591l-8.106 13.534a1.914 1.914 0 0 0 1.636 2.871h16.214a1.914 1.914 0 0 0 1.636 -2.87l-8.106 -13.536a1.914 1.914 0 0 0 -3.274 0z" /><path d="M12 16h.01" /></svg>)

  # Regexes
  @frontmatter_regex ~r/\A---\s*\n(?<frontmatter>.*?)\n---\s*\n(?<body>.*)\z/s
  @localized_link_regex ~r/<LocalizedLink\s+(?:href|to)="([^"]+)"\s*>(.*?)<\/LocalizedLink>/s
  @script_setup_regex ~r/<script\s+setup>.*?<\/script>\s*/s
  @custom_heading_id_regex ~r/^(\#{1,6}\s+.*?)\s+\{#([\w-]+)\}\s*$/m
  @heading_extract_regex ~r/^(\#{2,4})\s+(.+?)(?:\s+\{#([\w-]+)\})?\s*$/m
  @vitepress_container_regex ~r/^:::\s*(\w[\w-]*)([ \t]+[^\n]+)?\s*\n(.*?)^:::\s*$/ms
  @github_alert_regex ~r/<div class="markdown-alert markdown-alert-(\w+)">\s*<p class="markdown-alert-title">([^<]*)<\/p>\s*(.*?)\s*<\/div>/s
  @home_cards_regex ~r/<HomeCards>\s*(.*?)\s*<\/HomeCards>/s
  @home_card_icon_regex ~r/\s+icon="[^"]*"/
  @home_card_regex ~r/<HomeCard\s+([^>]*?)\/>/s
  @home_card_attr_regex ~r/(\w+)="([^"]*)"/
  @code_group_block_regex ~r/```(\w+)\s+\[([^\]]+)\]\n(.*?)```/s
  # Lookup maps
  @github_alert_type_to_status %{
    "note" => "information",
    "tip" => "success",
    "important" => "information",
    "warning" => "warning",
    "caution" => "error"
  }

  @admonition_type_to_status %{
    "info" => "information",
    "tip" => "success",
    "warning" => "warning",
    "danger" => "error"
  }

  # EEx templates
  @github_alert_template """
  <div class="noora-alert tuist-admonition" data-type="secondary" data-status="<%= status %>" data-size="large">\
  <div data-part="icon"><%= icon %></div>\
  <div data-part="column">\
  <span data-part="title"><%= title %></span>\
  <div data-part="description"><%= content %></div>\
  </div>\
  </div>\
  """

  @admonition_template """
  <div class="noora-alert tuist-admonition" data-type="secondary" data-status="<%= status %>" data-size="large">\
  <div data-part="icon"><%= icon %></div>\
  <div data-part="column">\
  <span data-part="title"><%= title_text %></span>\
  <div data-part="description">

  <%= content %>

  </div>\
  </div>\
  </div>
  """

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

  defp build_page!(source_path) do
    relative_path = Path.relative_to(source_path, @docs_root)
    slug = source_to_slug(relative_path)
    locale = relative_path |> String.split("/") |> List.first()
    contents = File.read!(source_path)

    {attrs, markdown} = parse_frontmatter(contents)
    headings = extract_headings(markdown)
    html = render_markdown(markdown, locale)

    %Page{
      slug: slug,
      title: attrs["title"] || title_from_markdown(markdown) || slug,
      title_template: attrs["titleTemplate"],
      description: attrs["description"],
      body: html,
      markdown: markdown,
      source_path: relative_path,
      headings: headings
    }
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

  defp build_example_page!(readme_path) do
    dir_name = readme_path |> Path.dirname() |> Path.basename()
    slug = "/en/references/examples/generated-projects/#{String.downcase(dir_name)}"
    markdown = File.read!(readme_path)
    title = title_from_markdown(markdown) || dir_name
    github_url = "https://github.com/tuist/tuist/tree/main/examples/xcode/#{dir_name}"

    markdown_with_link = markdown <> "\n\n[Check out example](#{github_url})\n"
    headings = extract_headings(markdown_with_link)
    html = render_markdown(markdown_with_link)

    %Page{
      slug: slug,
      title: title,
      title_template: ":title · Examples · References · Tuist",
      description: "Example: #{title}",
      body: html,
      markdown: markdown_with_link,
      source_path: readme_path,
      headings: headings
    }
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

  defp render_markdown(markdown, locale \\ "en") do
    custom_ids = extract_custom_heading_ids(markdown)

    processed_markdown =
      markdown
      |> String.replace(@script_setup_regex, "")
      |> localize_link_components(locale)
      |> convert_home_cards(locale)
      |> strip_custom_heading_ids()
      |> convert_vitepress_containers()

    [markdown: processed_markdown]
    |> MDEx.new()
    |> MDExMermaid.attach(mermaid_init: "")
    |> MDEx.to_html!(
      extension: [
        header_ids: "",
        autolink: true,
        table: true,
        strikethrough: true,
        tasklist: true,
        alerts: true
      ],
      syntax_highlight: [formatter: {:html_inline, theme: "github_light"}]
    )
    |> HTML.wrap_code_blocks()
    |> wrap_tables()
    |> convert_github_alerts()
    |> rewrite_image_paths()
    |> replace_heading_ids(custom_ids)
    |> HTML.add_heading_anchors()
  end

  defp convert_github_alerts(html) do
    Regex.replace(@github_alert_regex, html, fn _, type, title, content ->
      status = Map.get(@github_alert_type_to_status, type, "information")
      icon = admonition_icon(status)
      EEx.eval_string(@github_alert_template, status: status, icon: icon, title: title, content: content)
    end)
  end

  defp rewrite_image_paths(html) do
    html
    |> String.replace(~s(src="/images/), ~s(src="/docs/images/))
    |> String.replace(~s(src="/logo.png"), ~s(src="/docs/images/logo.webp"))
  end

  defp convert_home_cards(markdown, locale) do
    Regex.replace(@home_cards_regex, markdown, fn _, content ->
      content = Regex.replace(@home_card_icon_regex, content, "")

      cards =
        @home_card_regex
        |> Regex.scan(content)
        |> Enum.map_join("", fn [_, attrs_str] ->
          attrs =
            @home_card_attr_regex
            |> Regex.scan(attrs_str)
            |> Map.new(fn [_, key, value] -> {key, value} end)

          title = Map.get(attrs, "title", "")
          details = Map.get(attrs, "details", "")
          link = Map.get(attrs, "link", "")
          link_href = if link == "", do: "#", else: Paths.public_path(locale, link)

          EEx.eval_string(
            ~s(<a href="<%= link_href %>" class="docs-home-card"><div class="docs-home-card-image"><strong><%= title %></strong></div><div class="docs-home-card-body"><p><%= details %></p></div></a>),
            link_href: link_href,
            title: title,
            details: details
          )
        end)

      EEx.eval_string(~s(<div class="docs-home-cards"><%= cards %></div>\n), cards: cards)
    end)
  end

  defp wrap_tables(html) do
    html
    |> String.replace("<table>", ~s(<div class="noora-table"><table>))
    |> String.replace("</table>", "</table></div>")
  end

  defp localize_link_components(markdown, locale) do
    Regex.replace(@localized_link_regex, markdown, fn _, href, text ->
      EEx.eval_string(~s(<a href="<%= href %>"><%= text %></a>), href: localize_href(href, locale), text: text)
    end)
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

  defp convert_vitepress_containers(markdown) do
    Regex.replace(@vitepress_container_regex, markdown, fn _, type, title, content ->
      if type == "code-group" do
        convert_code_group(content)
      else
        convert_admonition(type, title, content)
      end
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

          EEx.eval_string(~s(<button data-part="tab" data-index="<%= index %>"<%= selected %>><%= label %></button>),
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

  defp convert_admonition(type, title, content) do
    title = if title, do: String.trim(title)
    status = Map.get(@admonition_type_to_status, type, "information")
    icon = admonition_icon(status)
    title_text = if title && title != "", do: capitalize_title(title), else: default_admonition_title(type)

    cleaned_content =
      content
      |> String.replace(~r/<!--\s*-->/, "")
      |> String.trim()

    EEx.eval_string(@admonition_template, status: status, icon: icon, title_text: title_text, content: cleaned_content)
  end

  defp admonition_icon("warning"), do: @alert_triangle_icon
  defp admonition_icon("success"), do: @circle_check_icon
  defp admonition_icon(_), do: @alert_circle_icon

  defp default_admonition_title("info"), do: "Info"
  defp default_admonition_title("tip"), do: "Tip"
  defp default_admonition_title("warning"), do: "Warning"
  defp default_admonition_title("danger"), do: "Danger"
  defp default_admonition_title(type), do: String.capitalize(type)

  defp capitalize_title(title) do
    title
    |> String.split(" ")
    |> Enum.map_join(" ", fn word ->
      word |> String.downcase() |> String.capitalize()
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

  defp localize_href("/" <> _ = href, locale) do
    slug = "/#{locale}" <> href
    Paths.public_path_from_slug(slug)
  end

  defp localize_href(href, _locale), do: href

  defp title_from_markdown(markdown) do
    case Regex.run(~r/^\s*#\s+(.+?)(?:\s+\{#.*\})?\s*$/m, markdown, capture: :all_but_first) do
      [title] -> String.trim(title)
      _ -> nil
    end
  end
end
