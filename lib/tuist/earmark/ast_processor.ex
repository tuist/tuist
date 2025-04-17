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
     {"div", [{"class", "marketing__component__window"}],
      [
        {"div", [{"class", "marketing__component__window__bar"}],
         [
           {"div", [{"class", "marketing__component__window__bar__close"}], [], %{}},
           {"div", [{"class", "marketing__component__window__bar__minimize"}], [], %{}},
           {"div", [{"class", "marketing__component__window__bar__maximize"}], [], %{}}
         ], %{}},
        {
          "div",
          [
            {"class", "marketing__component__window__content font-mono"}
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

  def process(node) do
    node
  end
end
