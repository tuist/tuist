defmodule Tuist.Marketing.Blog.MDExConverter do
  @moduledoc """
  Custom NimblePublisher HTML converter that uses MDEx instead of Earmark.
  Converts markdown to HTML at compile time with server-side syntax highlighting
  and support for Phoenix HEEx components.
  """

  def convert(_path, body, _attrs, _opts) do
    MDEx.to_html!(body,
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
        formatter: {:html_inline, theme: "onedark"}
      ]
    )
  end
end
