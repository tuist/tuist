defmodule Tuist.Docs.HTML do
  @moduledoc """
  Shared HTML post-processing helpers for documentation rendering.
  """

  @noora_icons_path Path.expand("../noora/lib/noora/icons", File.cwd!())
  @copy_icon @noora_icons_path |> Path.join("copy.svg") |> File.read!() |> String.trim()
  @copy_check_icon @noora_icons_path
                   |> Path.join("copy-check.svg")
                   |> File.read!()
                   |> String.trim()

  @code_block_regex ~r/<pre[^>]*><code(?:[^>]*class="language-(\w+)")?[^>]*>(.*?)<\/code><\/pre>/s
  @code_window_content_regex ~r/(<div data-part="code"><code>)(.*?)(<\/code>\s*<\/div>)/s
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

  def wrap_tables(html) do
    {html, code_contents} = protect_code_contents(html)
    {html, component_tags} = protect_component_tags(html)

    {html, _table_index} =
      html
      |> Floki.parse_fragment!()
      |> Floki.traverse_and_update(0, &wrap_table_node/2)

    html
    |> Floki.raw_html()
    |> restore_component_tags(component_tags)
    |> restore_protected_blocks(code_contents)
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

  defp protect_code_contents(html) do
    {html, code_contents} = do_protect_code_contents(html, 0, [])

    {IO.iodata_to_binary(html), code_contents}
  end

  defp do_protect_code_contents("", _index, code_contents), do: {[], code_contents}

  defp do_protect_code_contents(html, index, code_contents) do
    case Regex.run(@code_window_content_regex, html, return: :index) do
      nil ->
        {[html], code_contents}

      [
        {full_start, full_length},
        {open_start, open_length},
        {content_start, content_length},
        {close_start, close_length}
      ] ->
        before = binary_part(html, 0, full_start)
        open_tag = binary_part(html, open_start, open_length)
        code_content = binary_part(html, content_start, content_length)
        close_tag = binary_part(html, close_start, close_length)
        rest_start = full_start + full_length
        rest = binary_part(html, rest_start, byte_size(html) - rest_start)
        placeholder = "__TUIST_DOCS_HTML_CODE_CONTENT_#{index}__"

        {rest, code_contents} =
          do_protect_code_contents(rest, index + 1, [{placeholder, code_content} | code_contents])

        {[before, open_tag, placeholder, close_tag | rest], code_contents}
    end
  end

  # Floki normalizes custom component tag names, so keep those exact tags as
  # placeholders while traversing regular document nodes.
  defp protect_component_tags(html) do
    {html, component_tags} = do_protect_component_tags(html, 0, [])

    {IO.iodata_to_binary(html), component_tags}
  end

  defp do_protect_component_tags("", _index, component_tags), do: {[], component_tags}

  defp do_protect_component_tags(html, index, component_tags) do
    case :binary.match(html, "<") do
      :nomatch ->
        {[html], component_tags}

      {start_index, 1} ->
        before_tag = binary_part(html, 0, start_index)
        tag_and_rest = binary_part(html, start_index, byte_size(html) - start_index)

        case tag_end_index(tag_and_rest) do
          nil ->
            {[html], component_tags}

          end_index ->
            tag = binary_part(tag_and_rest, 0, end_index + 1)

            rest =
              binary_part(tag_and_rest, end_index + 1, byte_size(tag_and_rest) - end_index - 1)

            if component_tag?(tag) do
              placeholder = "__TUIST_DOCS_HTML_COMPONENT_TAG_#{index}__"

              {rest, component_tags} =
                do_protect_component_tags(rest, index + 1, [{placeholder, tag} | component_tags])

              {[before_tag, placeholder | rest], component_tags}
            else
              {rest, component_tags} = do_protect_component_tags(rest, index, component_tags)

              {[before_tag, tag | rest], component_tags}
            end
        end
    end
  end

  defp tag_end_index(tag), do: tag_end_index(tag, 1, nil)

  defp tag_end_index(tag, index, quote) when index < byte_size(tag) do
    case :binary.at(tag, index) do
      ?' when quote == nil -> tag_end_index(tag, index + 1, ?')
      ?' when quote == ?' -> tag_end_index(tag, index + 1, nil)
      ?" when quote == nil -> tag_end_index(tag, index + 1, ?")
      ?" when quote == ?" -> tag_end_index(tag, index + 1, nil)
      ?> when quote == nil -> index
      _other -> tag_end_index(tag, index + 1, quote)
    end
  end

  defp tag_end_index(_tag, _index, _quote), do: nil

  defp component_tag?("<" <> tag) do
    tag =
      tag
      |> String.trim_leading()
      |> String.trim_leading("/")

    case tag do
      "." <> _rest -> true
      <<first_character::utf8, _rest::binary>> when first_character in ?A..?Z -> true
      _other -> false
    end
  end

  defp restore_component_tags(html, component_tags) do
    restore_protected_blocks(html, component_tags)
  end

  defp restore_protected_blocks(html, blocks) do
    Enum.reduce(blocks, html, fn {placeholder, block}, html ->
      String.replace(html, placeholder, block)
    end)
  end

  defp wrap_table_node({"table", attrs, children}, table_index) do
    {
      {"div",
       [
         {"id", "docs-markdown-table-#{table_index}"},
         {"class", "noora-table"},
         {"phx-hook", "NooraTable"}
       ],
       [
         {"div", [{"data-part", "scroll-container"}],
          [
            {"table", attrs, children}
          ]},
         {"div", [{"data-part", "scrollbar"}, {"aria-hidden", "true"}],
          [
            {"div", [{"data-part", "scrollbar-content"}], []}
          ]},
         {"div", [{"data-part", "overlay-scrollbar"}, {"aria-hidden", "true"}],
          [
            {"div", [{"data-part", "overlay-thumb"}], []}
          ]}
       ]},
      table_index + 1
    }
  end

  defp wrap_table_node(node, table_index), do: {node, table_index}
end
