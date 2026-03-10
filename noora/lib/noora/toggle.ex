defmodule Noora.Toggle do
  @moduledoc """
  A toggle switch input.

  ## Example

  ```elixir
  <.toggle label="Enable notifications" />
  <.toggle />
  ```
  """

  use Phoenix.Component

  alias Phoenix.HTML.FormField

  attr(:label, :string, default: nil, doc: "The label of the toggle.")
  attr(:description, :string, default: nil, doc: "An optional description.")
  attr(:checked, :boolean, default: false, doc: "Whether the toggle is checked.")
  attr(:disabled, :boolean, default: false, doc: "Whether the toggle is disabled.")
  attr(:id, :string, default: nil, doc: "The id of the toggle.")
  attr(:name, :string, default: nil, doc: "The name of the toggle.")
  attr(:field, FormField, default: nil, doc: "A Phoenix form field.")
  attr(:tabindex, :integer, default: nil, doc: "Tabindex to add to the toggle control")

  attr(:rest, :global, doc: "Additional attributes")

  def toggle(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:checked, fn ->
      Phoenix.HTML.Form.normalize_value("checkbox", field.value)
    end)
    |> toggle()
  end

  def toggle(assigns) do
    ~H"""
    <div
      id={@id}
      name={@name}
      class="noora-toggle"
      phx-hook="NooraToggle"
      data-checked={@checked}
      data-disabled={@disabled}
      {@rest}
    >
      <label data-part="root">
        <input data-peer data-part="hidden-input" tabindex={@tabindex} />
        <div
          class="noora-toggle-control"
          data-state={if @checked, do: "checked", else: "unchecked"}
          data-disabled={@disabled}
          data-part="control"
        >
          <div data-part="track">
            <div data-part="thumb" />
          </div>
        </div>
        <div :if={@label}>
          <span data-part="label">{@label}</span>
          <span :if={@description} data-part="description">{@description}</span>
        </div>
      </label>
    </div>
    """
  end
end
