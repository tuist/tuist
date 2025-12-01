defmodule Tuist.Earmark.ASTProcessor do
  @moduledoc ~S"""
  This module overrides the processing logic of the Earmark library to customize the HTML output of code blocks and headings. Code blocks are wrapped in a window-like container and headings get an anchor link.
  """
  def process({"pre", _, [{"code", code_attrs, code_children, code_opts}], %{}}) do
    language =
      case Enum.find(code_attrs, fn
             {"class", _} -> true
             _ -> false
           end) do
        nil -> ""
        {_, language} -> language
      end

    {:replace,
     {"div", [{"id", "marketing-window"}],
      [
        {"div", [{"data-part", "bar"}],
         [
           {"div", [{"data-part", "language"}], [language], %{}},
           {"div", [{"data-part", "copy"}],
            [
              {"svg",
               [
                 {"width", "24"},
                 {"height", "24"},
                 {"viewBox", "0 0 24 24"},
                 {"fill", "none"},
                 {"xmlns", "http://www.w3.org/2000/svg"}
               ],
               [
                 {"path",
                  [
                    {"fill-rule", "evenodd"},
                    {"clip-rule", "evenodd"},
                    {"d",
                     "M8.5 8C8.22614 8 8 8.22614 8 8.5V13.4993C8.0003 13.5876 8.02386 13.6742 8.06831 13.7505C8.11285 13.827 8.17677 13.8903 8.25363 13.9341C8.49353 14.0709 8.57713 14.3762 8.44037 14.6161C8.30361 14.856 7.99827 14.9396 7.75837 14.8029C7.52857 14.6719 7.33742 14.4825 7.20426 14.254C7.0711 14.0254 7.00064 13.7657 7 13.5012L7 13.5V8.5C7 7.67386 7.67386 7 8.5 7H13.5C13.7812 7 14.0315 7.07491 14.2452 7.23005C14.4481 7.37734 14.5847 7.57311 14.687 7.757C14.8212 7.99833 14.7343 8.30277 14.493 8.43698C14.2517 8.57118 13.9472 8.48434 13.813 8.243C13.7443 8.11939 13.6934 8.06516 13.6578 8.03932C13.633 8.02134 13.5938 8 13.5 8H8.5ZM10.8335 10C10.6124 10 10.4004 10.0878 10.2441 10.2441C10.0878 10.4004 10 10.6124 10 10.8335V15.1665C10 15.276 10.0216 15.3843 10.0634 15.4855C10.1053 15.5866 10.1667 15.6785 10.2441 15.7559C10.3215 15.8333 10.4134 15.8947 10.5145 15.9366C10.6157 15.9784 10.724 16 10.8335 16H15.1665C15.276 16 15.3843 15.9784 15.4855 15.9366C15.5866 15.8947 15.6785 15.8333 15.7559 15.7559C15.8333 15.6785 15.8947 15.5866 15.9366 15.4855C15.9784 15.3843 16 15.276 16 15.1665V10.8335C16 10.724 15.9784 10.6157 15.9366 10.5145C15.8947 10.4134 15.8333 10.3215 15.7559 10.2441C15.6785 10.1667 15.5866 10.1053 15.4855 10.0634C15.3843 10.0216 15.276 10 15.1665 10H10.8335ZM9.53702 9.53702C9.88087 9.19317 10.3472 9 10.8335 9H15.1665C15.4073 9 15.6457 9.04743 15.8681 9.13957C16.0906 9.23171 16.2927 9.36676 16.463 9.53702C16.6332 9.70727 16.7683 9.9094 16.8604 10.1319C16.9526 10.3543 17 10.5927 17 10.8335V15.1665C17 15.4073 16.9526 15.6457 16.8604 15.8681C16.7683 16.0906 16.6332 16.2927 16.463 16.463C16.2927 16.6332 16.0906 16.7683 15.8681 16.8604C15.6457 16.9526 15.4073 17 15.1665 17H10.8335C10.5927 17 10.3543 16.9526 10.1319 16.8604C9.9094 16.7683 9.70727 16.6332 9.53702 16.463C9.36676 16.2927 9.23171 16.0906 9.13957 15.8681C9.04743 15.6457 9 15.4073 9 15.1665V10.8335C9 10.3472 9.19317 9.88087 9.53702 9.53702Z"},
                    {"fill", "#171A1C"}
                  ], [], %{}}
               ], %{}}
            ], %{}}
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

  def process({heading, attrs, [text], _}) when heading in ["h1", "h2", "h3", "h4", "h5"] do
    id =
      text
      |> String.downcase()
      |> String.replace(~r/\s+/, "-")

    {:replace,
     {heading,
      attrs ++
        [
          {"id", id},
          {"tabindex", "-1"},
          {"class", "marketing__blog_post__body__content__heading"}
        ],
      [
        text,
        {"a",
         [
           {"href", "\##{id}"},
           {"class", "marketing__blog_post__body__content__heading__anchor"},
           {"aria-label", "Permalink to #{text}"}
         ], [""], %{}}
      ], %{}}}
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
end
