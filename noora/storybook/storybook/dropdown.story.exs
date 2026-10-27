defmodule TuistWeb.Storybook.Dropdown do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Dropdown

  def function, do: &Dropdown.dropdown/1

  def imports, do: [{Dropdown, [dropdown_item: 1]}, {Noora.Icon, [category: 1, chevron_right: 1]}]

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          label: "Dropdown"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Item 1" />
          <.dropdown_item value="2" label="Item 2"><:right_icon><.chevron_right /></:right_icon></.dropdown_item>
          <.dropdown_item value="3" label="Item 3" secondary_text="Foo" />
          <.dropdown_item value="4" label="Item 4"><:left_icon><.category /></:left_icon></.dropdown_item>
          <.dropdown_item value="5" label="Item 5" />
          """
        ]
      },
      %Variation{
        id: :disabled,
        attributes: %{
          label: "Dropdown",
          disabled: true
        }
      },
      %Variation{
        id: :large_items,
        attributes: %{
          label: "Dropdown with large items"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Item 1" size="large">
          <:left_icon><.category /></:left_icon>
          </.dropdown_item>
          <.dropdown_item value="2" label="Item 2" size="large" right_icon={false}>
          <:left_icon><.category /></:left_icon>
          </.dropdown_item>
          <.dropdown_item value="3" label="Item 3" size="large" secondary_text="Foo">
          <:left_icon><.category /></:left_icon>
          </.dropdown_item>
          <.dropdown_item value="4" label="Item 4" size="large">
          <:left_icon><.category /></:left_icon>
          </.dropdown_item>
          <.dropdown_item value="5" label="Item 5" size="large">
          <:left_icon><.category /></:left_icon>
          </.dropdown_item>
          """
        ]
      },
      %Variation{
        id: :with_icon,
        description: "Dropdown with icon",
        attributes: %{
          label: "Dropdown"
        },
        slots: [
          """
          <:icon><.category /></:icon>
          <.dropdown_item value="1" label="Item 1"/>
          """
        ]
      },
      %Variation{
        id: :with_secondary_text,
        description: "Dropdown with secondary_text",
        attributes: %{
          label: "Date",
          secondary_text: "Order by"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Item 1" secondary_text="Foo"/>
          """
        ]
      },
      %Variation{
        id: :with_icon_and_secondary_text,
        description: "Dropdown with icon and secondary_text",
        attributes: %{
          label: "Date",
          secondary_text: "Order by"
        },
        slots: [
          """
          <:icon><.category /></:icon>
          <.dropdown_item value="1" label="Item 1" secondary_text="Foo"/>
          """
        ]
      },
      %Variation{
        id: :with_hint,
        description: "Dropdown with hint",
        attributes: %{
          label: "Dropdown",
          hint: "This is a hint"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Item 1"/>
          """
        ]
      },
      %Variation{
        id: :many_options,
        description: "Dropdown with many options to force scrolling",
        attributes: %{
          label: "Many Options"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Option 1" />
          <.dropdown_item value="2" label="Option 2" />
          <.dropdown_item value="3" label="Option 3" />
          <.dropdown_item value="4" label="Option 4" />
          <.dropdown_item value="5" label="Option 5" />
          <.dropdown_item value="6" label="Option 6" />
          <.dropdown_item value="7" label="Option 7" />
          <.dropdown_item value="8" label="Option 8" />
          <.dropdown_item value="9" label="Option 9" />
          <.dropdown_item value="10" label="Option 10" />
          <.dropdown_item value="11" label="Option 11" />
          <.dropdown_item value="12" label="Option 12" />
          <.dropdown_item value="13" label="Option 13" />
          <.dropdown_item value="14" label="Option 14" />
          <.dropdown_item value="15" label="Option 15" />
          <.dropdown_item value="16" label="Option 16" />
          <.dropdown_item value="17" label="Option 17" />
          <.dropdown_item value="18" label="Option 18" />
          <.dropdown_item value="19" label="Option 19" />
          <.dropdown_item value="20" label="Option 20" />
          """
        ]
      },
      %Variation{
        id: :with_custom_label,
        description: "Dropdown items with custom label content using inner_block",
        attributes: %{
          label: "Custom Labels"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Regular Label" />
          <.dropdown_item value="2">
            <strong>Bold Custom Label</strong>
          </.dropdown_item>
          <.dropdown_item value="3">
            <span style="color: #6366f1;">Colored Custom Label</span>
          </.dropdown_item>
          <.dropdown_item value="4">
            <.category /> Item with Icon in Label
          </.dropdown_item>
          """
        ]
      },
      %Variation{
        id: :with_checkboxes,
        description: "Dropdown with checkbox items for multi-select",
        attributes: %{
          label: "Select days"
        },
        slots: [
          """
          <.dropdown_item value="monday" label="Monday" checked={true} />
          <.dropdown_item value="tuesday" label="Tuesday" checked={true} />
          <.dropdown_item value="wednesday" label="Wednesday" checked={false} />
          <.dropdown_item value="thursday" label="Thursday" checked={false} />
          <.dropdown_item value="friday" label="Friday" checked={true} />
          <.dropdown_item value="saturday" label="Saturday" checked={false} />
          <.dropdown_item value="sunday" label="Sunday" checked={false} />
          """
        ]
      }
    ]
  end
end
