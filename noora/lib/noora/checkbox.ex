defmodule Noora.Checkbox do
  @moduledoc """
  An input checkbox.

  ## Example

  ```elixir
  <.checkbox label="I agree to the terms" />
  ```
  """

  use Phoenix.Component

  import Noora.CheckboxControl

  alias Phoenix.HTML.FormField

  attr(:label, :string, required: true, doc: "The label of the checkbox.")
  attr(:description, :string, default: nil, doc: "An optional description.")
  attr(:indeterminate, :boolean, default: false, doc: "Whether the checkbox is indeterminate.")
  attr(:disabled, :boolean, default: false, doc: "Whether the checkbox is disabled.")
  attr(:id, :string, default: nil, doc: "The id of the checkbox.")
  attr(:name, :string, doc: "The name of the checkbox.")
  attr(:field, FormField, default: nil, doc: "A Phoenix form field.")
  attr(:tabindex, :integer, default: nil, doc: "Tabindex to add to the checkbox control")

  attr(:multiple, :boolean,
    default: false,
    doc: "Whether the checkbox is part of a multiple checkbox group."
  )

  attr(:rest, :global, doc: "Additional attributes")

  def checkbox(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> checkbox()
  end

  def checkbox(assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div
      id={@id}
      name={@name}
      class="noora-checkbox"
      phx-hook="NooraCheckbox"
      data-indeterminate={@indeterminate}
      data-disabled={@disabled}
      {@rest}
    >
      <label data-part="root">
        <input data-peer data-part="hidden-input" tabindex={@tabindex} />
        <.checkbox_control checked={@checked} indeterminate={@indeterminate} data-part="control" />
        <div>
          <span data-part="label">{@label}</span>
          <span :if={@description} data-part="description">{@description}</span>
        </div>
      </label>
    </div>
    """
  end
end
