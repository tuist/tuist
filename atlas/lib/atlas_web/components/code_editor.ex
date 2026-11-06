defmodule AtlasWeb.CodeEditor do
  @moduledoc "A native form textarea progressively enhanced with bounded, local syntax highlighting."

  use Phoenix.Component

  import Noora.TextArea, only: [text_area: 1]

  alias Phoenix.HTML.FormField

  attr :field, FormField, required: true
  attr :label, :string, required: true
  attr :language, :string, default: "json", values: ~w(json javascript)

  def code_editor(assigns) do
    ~H"""
    <div
      id={"#{@field.id}-editor"}
      data-part="code-editor"
      data-language={@language}
      phx-hook="CodeEditor"
    >
      <.text_area
        field={@field}
        label={@label}
        rows={12}
        max_length={65_536}
        show_character_count={false}
        data-part="code-editor-input"
        aria-label={@label}
        spellcheck="false"
        autocapitalize="off"
        autocorrect="off"
        autocomplete="off"
      />
      <pre
        id={"#{@field.id}-highlight"}
        data-part="code-editor-highlight"
        phx-update="ignore"
        aria-hidden="true"
      ><code></code></pre>
    </div>
    """
  end
end
