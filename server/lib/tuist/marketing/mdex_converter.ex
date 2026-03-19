defmodule Tuist.Marketing.MDExConverter do
  @moduledoc """
  Custom NimblePublisher HTML converter that uses MDEx instead of Earmark.
  Converts markdown to HTML at compile time with server-side syntax highlighting
  and support for Phoenix HEEx components.

  Code blocks are wrapped in a marketing window container with a language label
  and copy button, matching the design used across the marketing site.
  """

  alias Phoenix.HTML.Safe

  @copy_icon %{__changed__: nil} |> Noora.Icon.copy() |> Safe.to_iodata() |> IO.iodata_to_binary()
  @copy_check_icon %{__changed__: nil} |> Noora.Icon.copy_check() |> Safe.to_iodata() |> IO.iodata_to_binary()

  @mdex_options [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      header_ids: "",
      phoenix_heex: true
    ],
    parse: [
      smart: false,
      relaxed_autolinks: true
    ],
    render: [
      unsafe: true
    ],
    syntax_highlight: [
      formatter: {:html_inline, theme: "github_light"}
    ]
  ]

  def convert(_path, body, _attrs, _opts) do
    [markdown: body]
    |> MDEx.new()
    |> MDEx.Document.put_options(@mdex_options)
    |> MDEx.Document.append_steps(wrap_code_blocks: &wrap_code_blocks/1)
    |> MDEx.to_html!()
  end

  defp wrap_code_blocks(document) do
    MDEx.traverse_and_update(document, fn
      %MDEx.CodeBlock{info: info, literal: literal} ->
        highlighted_html =
          MDEx.to_html!(
            "```#{info}\n#{literal}```",
            @mdex_options
          )

        language = info |> String.split(~r/\s/, parts: 2) |> List.first() || ""

        %MDEx.HtmlBlock{
          literal: """
          <div data-part="marketing-window">\
          <div data-part="bar">\
          <div data-part="language">#{language}</div>\
          <div data-part="copy">\
          <span data-icon="copy">#{@copy_icon}</span>\
          <span data-icon="copy-check" style="display:none">#{@copy_check_icon}</span>\
          </div>\
          </div>\
          <div data-part="code">#{highlighted_html}</div>\
          </div>
          """
        }

      node ->
        node
    end)
  end
end
