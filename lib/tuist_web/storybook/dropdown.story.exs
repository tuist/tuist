defmodule TuistWeb.Storybook.Dropdown do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Dropdown.dropdown/1

  def imports,
    do: [{TuistWeb.Noora.Dropdown, [dropdown_item: 1]}, {TuistWeb.Noora.Icon, [category: 1]}]

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
          <.dropdown_item value="2" label="Item 2" right_icon={false} />
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
      }
    ]
  end
end
