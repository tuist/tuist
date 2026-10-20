defmodule TuistWeb.Noora.Code do
  @moduledoc """
  Highlights the code shown on the Noora documentation pages.

  Uses the same light and dark themes as the blog, so code samples follow the
  page's color scheme.
  """

  @mdex_options [
    syntax_highlight: [
      formatter: {:html_multi_themes, themes: [light: "github_light", dark: "github_dark"], default_theme: "light-dark()"}
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
