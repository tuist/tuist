defmodule Tuist.Earmark.ASTProcessor do
  @moduledoc ~S"""
  This module overrides the processing logic of the Earmark library to customize the HTML output of code blocks and headings. Code blocks are wrapped in a window-like container and headings get an anchor link.
  """

  @noora_icons_path Path.join([Mix.Project.deps_path(), "noora", "lib", "noora", "icons"])
  @copy_icon @noora_icons_path |> Path.join("copy.svg") |> File.read!() |> String.trim()
  @copy_check_icon @noora_icons_path |> Path.join("copy-check.svg") |> File.read!() |> String.trim()

  def process({"pre", _, [{"code", code_attrs, code_children, code_opts}], %{}}) do
    language =
      case Enum.find(code_attrs, fn
             {"class", _} -> true
             _ -> false
           end) do
        nil -> ""
        {_, language} -> language
      end

    copy_icon_html =
      ~s(<span data-part="copy-icon">#{@copy_icon}</span><span data-part="copy-check-icon">#{@copy_check_icon}</span>)

    {:replace,
     {"div", [{"class", "code-window"}],
      [
        {"div", [{"data-part", "bar"}],
         [
           {"div", [{"data-part", "language"}], [language], %{}},
           {"div", [{"data-part", "copy"}], [copy_icon_html], %{}}
         ], %{}},
        {
          "div",
          [
            {"data-part", "code"}
          ],
          [
            {"shiki-highlight", [{"language", language}], code_children, code_opts}
          ],
          %{}
        }
      ], %{}}}
  end

  def process({heading, attrs, children, _} = node) when heading in ["h1", "h2", "h3", "h4", "h5"] do
    text = heading_text(children)

    if text == "" do
      node
    else
      id =
        text
        |> String.downcase()
        |> String.replace(~r/\s+/, "-")

      stripped_children = strip_links(children)

      {:replace,
       {heading,
        attrs ++
          [
            {"id", id},
            {"tabindex", "-1"},
            {"class", "marketing__blog_post__body__content__heading"}
          ],
        stripped_children ++
          [
            {"a",
             [
               {"href", "\##{id}"},
               {"class", "marketing__blog_post__body__content__heading__anchor"},
               {"aria-label", "Permalink to #{text}"}
             ], [""], %{}}
          ], %{}}}
    end
  end

  def process({"prose_banner", attrs, [], %{}}) do
    title = Enum.find_value(attrs, "", fn {key, val} -> if key == "title", do: val end)

    description =
      Enum.find_value(attrs, "", fn {key, val} -> if key == "description", do: val end)

    cta_title = Enum.find_value(attrs, nil, fn {key, val} -> if key == "cta_title", do: val end)
    cta_href = Enum.find_value(attrs, nil, fn {key, val} -> if key == "cta_href", do: val end)

    # Create a unique marker that will be replaced with the component
    marker_id = 8 |> :crypto.strong_rand_bytes() |> Base.encode16()

    button_placeholder =
      if cta_title && cta_href do
        [
          {"prose-banner-button-marker",
           [
             {"data-marker-id", marker_id},
             {"data-cta-title", cta_title},
             {"data-cta-href", cta_href}
           ], [], %{}}
        ]
      else
        []
      end

    {:replace,
     {"div", [{"id", "marketing-prose-banner"}],
      [
        {"svg",
         [
           {"width", "24"},
           {"height", "24"},
           {"viewBox", "0 0 24 24"},
           {"fill", "none"},
           {"xmlns", "http://www.w3.org/2000/svg"},
           {"data-part", "icon"}
         ],
         [
           {"circle",
            [
              {"cx", "12"},
              {"cy", "12"},
              {"r", "10"},
              {"stroke", "currentColor"},
              {"stroke-width", "2"}
            ], [], %{}},
           {"path",
            [
              {"d", "M12 16V12"},
              {"stroke", "currentColor"},
              {"stroke-width", "2"},
              {"stroke-linecap", "round"}
            ], [], %{}},
           {"circle",
            [
              {"cx", "12"},
              {"cy", "8"},
              {"r", "1"},
              {"fill", "currentColor"}
            ], [], %{}}
         ], %{}},
        {"div", [{"data-part", "wrapper"}],
         [
           {"div", [{"data-part", "content"}],
            [
              {"div", [{"data-part", "title"}], [title], %{}},
              {"div", [{"data-part", "description"}], [description], %{}}
            ], %{}}
         ] ++ button_placeholder, %{}}
      ], %{}}}
  end

  def process(node) do
    node
  end

  defp strip_links(children) when is_list(children) do
    Enum.flat_map(children, fn
      {"a", _, inner, _} -> strip_links(inner)
      {tag, attrs, inner, meta} -> [{tag, attrs, strip_links(inner), meta}]
      other -> [other]
    end)
  end

  defp heading_text(children) do
    children
    |> Enum.map_join("", &node_text/1)
    |> String.trim()
  end

  defp node_text(value) when is_binary(value), do: value
  defp node_text(values) when is_list(values), do: Enum.map_join(values, "", &node_text/1)
  defp node_text({_, _, values, _}), do: node_text(values)
  defp node_text(_), do: ""
end
