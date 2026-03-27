defmodule Noora.Select do
  @moduledoc """
  A select dropdown component for choosing from a list of options.

  ## Example

  ```elixir
  <.select id="country" label="Select Country" name="country" value="us">
    <:item value="us" label="United States" icon="flag" />
    <:item value="ca" label="Canada" icon="flag" />
    <:item value="uk" label="United Kingdom" icon="flag" />
  </.select>
  ```
  """
  use Phoenix.Component

  import Noora.Dropdown
  import Noora.Icon

  alias Phoenix.HTML.FormField

  attr(:id, :string, required: true, doc: "Unique identifier for the dropdown component")

  attr(:label, :string, required: true, doc: "Main text displayed in the dropdown trigger")

  attr(:field, FormField, doc: "A Phoenix form field")

  attr(:name, :string, doc: "The name attribute for the select input")
  attr(:value, :string, doc: "The currently selected value")
  attr(:hint, :string, default: nil, doc: "Hint text for the dropdown")

  attr(:disabled, :boolean, default: nil, doc: "Whether the dropdown is disabled")

  attr(:on_value_change, :string,
    default: nil,
    doc: "Event handler for when an option is selected"
  )

  slot(:inner_block, doc: "Content to be rendered inside the dropdown menu")

  slot :item do
    attr(:icon, :string)
    attr(:label, :string)
    attr(:value, :string)
  end

  def select(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: Map.get(assigns, :id, field.id))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> select()
  end

  def select(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-dropdown"
      phx-hook="NooraSelect"
      data-name={@name}
      data-on-value-change={@on_value_change}
    >
      <button data-part="trigger" disabled={@disabled} type="button">
        <div data-part="label-wrapper">
          <div :if={Enum.find(@item, &(&1.value == @value))[:icon]} data-part="icon">
            <.icon name={Enum.find(@item, &(&1.value == @value))[:icon]} />
          </div>
          <span data-part="label">{Enum.find(@item, &(&1.value == @value))[:label] || @label}</span>
        </div>
        <div data-part="indicator">
          <div data-part="indicator-down">
            <.chevron_down />
          </div>
          <div data-part="indicator-up">
            <.chevron_up />
          </div>
        </div>
      </button>
      <div data-part="positioner">
        <div class="noora-dropdown-content" data-part="content">
          <.dropdown_item
            :for={item <- @item}
            data-part="item"
            value={item.value}
            label={item.label}
            class="noora-dropdown-item"
          >
            <:left_icon :if={Map.has_key?(item, :icon)}><.icon name={item.icon} /></:left_icon>
            {item.label}
          </.dropdown_item>
        </div>
      </div>
      <span :if={@hint} data-part="hint">
        <.info_circle />
        <span>{@hint}</span>
      </span>
    </div>
    """
  end
end
