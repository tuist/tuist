defmodule Tuist.Marketing.MDExConverter do
  @moduledoc """
  Compile-time MDEx helper for marketing blog content.

  It converts markdown to HTML for all existing consumers and can also
  precompile selected posts into a HEEx template that is rendered later with
  runtime assigns from LiveView.
  """

  use Noora

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

  def convert(_path, body, _attrs, _opts), do: body

  def compile_markdown(markdown, path, live?) do
    document = build_document(markdown)
    html = MDEx.to_html!(document)

    template =
      if live? do
        compile_heex_template(html, path)
      end

    {html, template}
  end

  defp build_document(markdown) do
    [markdown: markdown]
    |> MDEx.new()
    |> MDEx.Document.put_options(@mdex_options)
    |> MDEx.Document.append_steps(wrap_code_blocks: &wrap_code_blocks/1)
  end

  defp compile_heex_template(html, path) do
    env = __ENV__

    EEx.compile_string(
      html,
      engine: Phoenix.LiveView.TagEngine,
      file: path,
      line: 1,
      caller: env,
      indentation: 0,
      source: html,
      tag_handler: Phoenix.LiveView.HTMLEngine
    )
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
          <div class="marketing-window">\
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
