defmodule Tuist.Marketing.MDExConverter do
  @moduledoc """
  Compile-time MDEx helper for marketing blog content.

  It converts markdown to HTML for all existing consumers and can also
  precompile selected posts into a HEEx template that is rendered later with
  runtime assigns from LiveView.
  """

  use Noora

  alias Phoenix.HTML.Safe
  alias Tuist.Markdown

  @copy_icon %{__changed__: nil} |> Noora.Icon.copy() |> Safe.to_iodata() |> IO.iodata_to_binary()
  @copy_check_icon %{__changed__: nil} |> Noora.Icon.copy_check() |> Safe.to_iodata() |> IO.iodata_to_binary()

  @mdex_options [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      header_ids: "",
      phoenix_heex: true,
      alerts: true
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
        language = info |> String.split(~r/\s/, parts: 2) |> List.first() || ""

        if language == "mermaid" do
          mermaid_block(literal)
        else
          code_window(info, literal, language)
        end

      %MDEx.Alert{} = alert ->
        alert_block(alert)

      node ->
        node
    end)
  end

  defp alert_block(%MDEx.Alert{alert_type: alert_type, nodes: nodes}) do
    {status, title} = alert_meta(alert_type)
    body = MDEx.to_html!(%MDEx.Document{nodes: nodes}, @mdex_options)

    assigns = %{
      __changed__: nil,
      id: nil,
      type: "primary",
      status: status,
      size: "large",
      dismissible: false,
      show_icon: true,
      title: title,
      description: nil,
      action: [],
      rest: %{},
      inner_block: [
        %{__slot__: :inner_block, inner_block: fn _changed, _arg -> Phoenix.HTML.raw(body) end}
      ]
    }

    html =
      assigns
      |> Noora.Alert.alert()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> String.replace(~r/<!--.*?-->/s, "")

    %MDEx.HtmlBlock{literal: html}
  end

  defp alert_meta(:note), do: {"information", "Note"}
  defp alert_meta(:tip), do: {"success", "Tip"}
  defp alert_meta(:important), do: {"information", "Important"}
  defp alert_meta(:warning), do: {"warning", "Warning"}
  defp alert_meta(:caution), do: {"error", "Caution"}
  defp alert_meta(_), do: {"information", "Note"}

  defp mermaid_block(literal) do
    diagram = literal |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    id = "mermaid-" <> Integer.to_string(:erlang.phash2(literal))

    %MDEx.HtmlBlock{
      literal: ~s(<div id="#{id}" phx-update="ignore"><pre class="mermaid">#{diagram}</pre></div>)
    }
  end

  defp code_window(info, literal, language) do
    highlighted_html =
      "```#{info}\n#{literal}```"
      |> MDEx.to_html!(@mdex_options)
      |> protect_highlight_whitespace()

    copy_source = literal |> String.trim() |> Markdown.html_escape()

    %MDEx.HtmlBlock{
      literal: """
      <div class="code-window">\
      <div data-part="bar">\
      <div data-part="language">#{language}</div>\
      <div data-part="copy"><span data-part="copy-icon">#{@copy_icon}</span><span data-part="copy-check-icon">#{@copy_check_icon}</span></div>\
      </div>\
      <template data-part="copy-source">#{copy_source}</template>\
      <div data-part="code">#{highlighted_html}</div>\
      </div>
      """
    }
  end

  defp protect_highlight_whitespace(html) do
    Regex.replace(~r/(?<=>)([ \t]+)(?=<)/, html, fn _match, whitespace ->
      whitespace
      |> String.graphemes()
      |> Enum.map_join(&highlight_whitespace/1)
    end)
  end

  defp highlight_whitespace(" "), do: ~s(<span data-code-whitespace="true">&nbsp;</span>)
  defp highlight_whitespace("\t"), do: ~s(<span data-code-whitespace="true">\t</span>)
end
