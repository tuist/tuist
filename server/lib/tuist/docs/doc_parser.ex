defmodule Tuist.Docs.DocParser do
  @moduledoc false
  def parse(_path, contents) do
    {frontmatter, body} = split_frontmatter(contents)
    html = body |> preprocess() |> render_markdown() |> add_heading_ids()
    {frontmatter, html}
  end

  defp split_frontmatter(contents) do
    case Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, contents) do
      [_, frontmatter_string, body] ->
        frontmatter = Jason.decode!(frontmatter_string)
        {frontmatter, body}

      nil ->
        {%{}, contents}
    end
  end

  defp preprocess(body) do
    body
    |> strip_vue_components()
    |> convert_localized_links()
    |> convert_admonitions()
    |> convert_code_groups()
    |> strip_heading_anchors()
    |> strip_html_comments()
  end

  defp strip_vue_components(body) do
    body
    |> String.replace(~r/<script setup>.*?<\/script>/s, "")
    |> String.replace(~r/<HomeCards[^>]*>.*?<\/HomeCards>/s, "")
    |> String.replace(~r/<HomeCard[^>]*\/>/s, "")
    |> String.replace(~r/<HomeVideos\s*\/>/s, "")
    |> String.replace(~r/<HomeCommunity>.*?<\/HomeCommunity>/s, "")
    |> String.replace(~r/<VPFeatures[^>]*\/>/s, "")
  end

  defp convert_localized_links(body) do
    Regex.replace(
      ~r/<LocalizedLink\s+href="([^"]+)"\s*>(.*?)<\/LocalizedLink>/s,
      body,
      fn _, href, text ->
        link_href =
          if String.starts_with?(href, "/") do
            "/docs" <> href
          else
            href
          end

        "[#{text}](#{link_href})"
      end
    )
  end

  defp convert_admonitions(body) do
    Regex.replace(
      ~r/::: (info|tip|warning|danger)([^\n]*)\n<!-- -->\n(.*?)\n<!-- -->\n:::/s,
      body,
      fn _, type, title, content ->
        title = String.trim(title)

        display_title =
          if title == "" do
            String.upcase(type)
          else
            title
          end

        class =
          case type do
            "info" -> "docs-admonition-info"
            "tip" -> "docs-admonition-tip"
            "warning" -> "docs-admonition-warning"
            "danger" -> "docs-admonition-danger"
            _ -> "docs-admonition-info"
          end

        """
        <div class="docs-admonition #{class}">
        <p class="docs-admonition-title">#{display_title}</p>

        #{content}
        </div>
        """
      end
    )
  end

  defp convert_code_groups(body) do
    Regex.replace(
      ~r/::: code-group\n(.*?)\n:::/s,
      body,
      fn _, inner -> inner end
    )
  end

  defp strip_heading_anchors(body) do
    Regex.replace(~r/\s*\{#[a-zA-Z0-9_-]+\}/, body, "")
  end

  defp strip_html_comments(body) do
    String.replace(body, ~r/<!--.*?-->/s, "")
  end

  defp add_heading_ids(html) do
    Regex.replace(~r/<(h[2-4])>(.*?)<\/\1>/s, html, fn _full, tag, content ->
      text = String.replace(content, ~r/<[^>]+>/, "")

      id =
        text
        |> String.downcase()
        |> String.replace(~r/[^\w\s-]/, "")
        |> String.trim()
        |> String.replace(~r/\s+/, "-")

      "<#{tag} id=\"#{id}\">#{content}</#{tag}>"
    end)
  end

  defp render_markdown(body) do
    MDEx.to_html!(body,
      extension: [
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true
      ],
      parse: [
        smart: true,
        relaxed_autolinks: true
      ],
      render: [
        unsafe_: true
      ]
    )
  end
end
