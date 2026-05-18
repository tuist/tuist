defmodule Tuist.Docs.HTML do
  @moduledoc """
  Shared HTML post-processing helpers for documentation rendering.
  """

  @noora_icons_path Path.expand("../noora/lib/noora/icons", File.cwd!())
  @copy_icon @noora_icons_path |> Path.join("copy.svg") |> File.read!() |> String.trim()
  @copy_check_icon @noora_icons_path |> Path.join("copy-check.svg") |> File.read!() |> String.trim()

  @code_block_regex ~r/<pre[^>]*><code(?:[^>]*class="language-(\w+)")?[^>]*>(.*?)<\/code><\/pre>/s
  @heading_anchor_regex ~r/(<h[2-4]>)(<a href="#[^"]*" aria-hidden="true" class="anchor" id="[^"]*"><\/a>)(.*?)(<\/h[2-4]>)/s

  @code_block_template """
  <div class="code-window">\
  <div data-part="bar">\
  <div data-part="language"><%= language %></div>\
  <div data-part="copy"><span data-part="copy-icon"><%= copy_icon %></span><span data-part="copy-check-icon"><%= copy_check_icon %></span></div>\
  </div>\
  <div data-part="code"><code><%= code %></code>\
  </div>\
  </div>\
  """

  @heading_anchor_template """
  <%= open_tag %><a class="heading-anchor" id="<%= id %>" href="<%= href %>">\
  <span data-part="heading-text"><%= plain_text %></span>\
  <span data-part="hash">#</span>\
  </a><%= close_tag %>\
  """

  def wrap_code_blocks(html) do
    Regex.replace(@code_block_regex, html, fn _, language, code ->
      language = if language == "", do: "", else: language

      EEx.eval_string(@code_block_template,
        language: language,
        code: code,
        copy_icon: @copy_icon,
        copy_check_icon: @copy_check_icon
      )
    end)
  end

  def add_heading_anchors(html) do
    Regex.replace(@heading_anchor_regex, html, fn _, open_tag, anchor, text, close_tag ->
      href = ~r/href="([^"]*)"/ |> Regex.run(anchor, capture: :all_but_first) |> List.first()
      id = ~r/id="([^"]*)"/ |> Regex.run(anchor, capture: :all_but_first) |> List.first()
      plain_text = strip_links(text)

      EEx.eval_string(@heading_anchor_template,
        open_tag: open_tag,
        close_tag: close_tag,
        href: href,
        id: id,
        plain_text: plain_text
      )
    end)
  end

  defp strip_links(html) do
    Regex.replace(~r/<a[^>]*>(.*?)<\/a>/s, html, "\\1")
  end
end
