defmodule TuistWeb.Components.JSONInput do
  @moduledoc """
  A native JSON textarea progressively enhanced with Lumis syntax highlighting.
  """

  use Phoenix.Component

  import Noora.TextArea
  import Phoenix.HTML, only: [raw: 1]

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :error, :string, default: nil
  attr :hint, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :rows, :integer, default: 4

  def json_input(assigns) do
    assigns = assign(assigns, :highlighted, highlight(assigns.value))

    ~H"""
    <div class="json-input">
      <.text_area
        id={@id}
        name={@name}
        value={@value}
        label={@label}
        aria-label={@label}
        aria-invalid={not is_nil(@error)}
        error={@error}
        hint={@hint}
        placeholder={@placeholder}
        rows={@rows}
        max_length={8192}
        show_character_count={false}
        spellcheck="false"
        autocapitalize="off"
        autocorrect="off"
        phx-hook="JSONInput"
        phx-debounce="150"
      >
        <:overlay>
          <div :if={@highlighted} data-part="highlight" data-source={@value}>
            {raw(@highlighted)}
          </div>
        </:overlay>
      </.text_area>
    </div>
    """
  end

  defp highlight(value) when byte_size(value) > 0 and byte_size(value) <= 8192 do
    Lumis.highlight!(value, language: "json", formatter: :html_linked)
  rescue
    Lumis.HighlightError -> nil
  end

  defp highlight(_value), do: nil
end
