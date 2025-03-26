defmodule TuistWeb.Noora.Checkbox do
  @moduledoc """
  An input checkbox.
  """

  use Phoenix.Component
  import TuistWeb.Noora.Icon

  attr :label, :string, required: true, doc: "The label of the checkbox."
  attr :description, :string, default: nil, doc: "An optional description."
  attr :indeterminate, :boolean, default: false, doc: "Whether the checkbox is indeterminate."
  attr :disabled, :boolean, default: false, doc: "Whether the checkbox is disabled."

  attr :multiple, :boolean,
    default: false,
    doc: "Whether the checkbox is part of a multiple checkbox group."

  def checkbox(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
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
      class="noora-checkbox"
      phx-hook="NooraCheckbox"
      data-indeterminate={@indeterminate}
      data-disabled={@disabled}
    >
      <label data-part="root">
        <input data-part="hidden-input" />
        <div data-part="control">
          <div data-part="check"><.check /></div>
          <div data-part="minus"><.minus /></div>
        </div>
        <div>
          <span data-part="label">{@label}</span>
          <span :if={@description} data-part="description">{@description}</span>
        </div>
      </label>
    </div>
    """
  end
end
