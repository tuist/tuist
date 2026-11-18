defmodule TuistWeb.Noora.Code do
  @moduledoc """
  Highlights the code shown on the Noora documentation pages.

  Emits CSS classes, colored with Noora tokens by
  `assets/shared/css/syntax.css`, the same as the blog and the docs.
  """

  @mdex_options [
    syntax_highlight: [
      formatter: :html_linked
    ]
  ]

  def highlight(source, language \\ "heex") do
    "```#{language}\n#{source}\n```"
    |> MDEx.to_html!(@mdex_options)
    |> protect_whitespace()
  end

  # Runs of spaces between highlighted tokens would collapse in the
  # LiveView-rendered DOM, flattening the code's indentation.
  defp protect_whitespace(html) do
    Regex.replace(~r/(?<=>)([ \t]+)(?=<)/, html, fn _match, whitespace ->
      whitespace
      |> String.graphemes()
      |> Enum.map_join(fn
        " " -> ~s(<span data-code-whitespace="true">&nbsp;</span>)
        "\t" -> ~s(<span data-code-whitespace="true">\t</span>)
      end)
    end)
  end
end
