defmodule Noora.Radio do
  @moduledoc """
  A radio button, and a group that lets people pick one option from a set.

  ## Example

  ```elixir
  <.radio_group name="visibility" value="private" label="Visibility">
    <:radio value="private" label="Private" />
    <:radio value="public" label="Public" />
  </.radio_group>
  ```
  """

  use Phoenix.Component

  import Noora.RadioControl

  alias Phoenix.HTML.FormField

  attr(:label, :string, required: true, doc: "The label of the radio.")
  attr(:description, :string, default: nil, doc: "An optional description.")
  attr(:value, :any, required: true, doc: "The value submitted when the radio is selected.")
  attr(:name, :string, default: nil, doc: "The name shared by the radios of one group.")
  attr(:checked, :boolean, default: false, doc: "Whether the radio is selected.")
  attr(:disabled, :boolean, default: false, doc: "Whether the radio is disabled.")
  attr(:id, :string, default: nil, doc: "The id of the radio input.")
  attr(:tabindex, :integer, default: nil, doc: "Tabindex to add to the radio input.")

  attr(:rest, :global,
    include: ~w(form required),
    doc: "Additional attributes, added to the radio input."
  )

  def radio(assigns) do
    ~H"""
    <label class="noora-radio">
      <input
        type="radio"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        disabled={@disabled}
        tabindex={@tabindex}
        data-part="input"
        {@rest}
      />
      <.radio_control data-part="control" />
      <span data-part="label">{@label}</span>
      <span :if={@description} data-part="description">{@description}</span>
    </label>
    """
  end

  attr(:name, :string, doc: "The name the selected value is submitted under.")
  attr(:value, :any, doc: "The value of the selected radio.")
  attr(:field, FormField, default: nil, doc: "A Phoenix form field.")
  attr(:label, :string, default: nil, doc: "Names the group, as its legend.")
  attr(:id, :string, default: nil, doc: "The id of the group.")
  attr(:disabled, :boolean, default: false, doc: "Whether every radio in the group is disabled.")

  attr(:orientation, :string,
    values: ~w(vertical horizontal),
    default: "vertical",
    doc: "Whether the radios stack or sit in a row."
  )

  attr(:rest, :global, doc: "Additional attributes")

  slot :radio, required: true, doc: "A radio of the group." do
    attr(:value, :any, required: true, doc: "The value submitted when the radio is selected.")
    attr(:label, :string, required: true, doc: "The label of the radio.")
    attr(:description, :string, doc: "An optional description.")
    attr(:disabled, :boolean, doc: "Whether the radio is disabled.")
  end

  def radio_group(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> radio_group()
  end

  def radio_group(assigns) do
    assigns =
      assigns
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:value, fn -> nil end)

    ~H"""
    <fieldset
      id={@id}
      class="noora-radio-group"
      data-orientation={@orientation}
      disabled={@disabled}
      {@rest}
    >
      <legend :if={@label} data-part="label">{@label}</legend>
      <div data-part="items">
        <.radio
          :for={radio <- @radio}
          id={@id && "#{@id}-#{radio.value}"}
          name={@name}
          value={radio.value}
          label={radio.label}
          description={radio[:description]}
          disabled={radio[:disabled] || false}
          checked={selected?(@value, radio.value)}
        />
      </div>
    </fieldset>
    """
  end

  defp selected?(nil, _value), do: false
  defp selected?(selected, value), do: to_string(selected) == to_string(value)
end
