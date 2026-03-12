defmodule TuistWeb.Storybook.InlineDropdown do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Dropdown

  def function, do: &Dropdown.inline_dropdown/1

  def imports, do: [{Dropdown, [dropdown_item: 1]}, {Noora.Icon, [category: 1, chevron_right: 1]}]

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          label: "Inline Dropdown"
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
          label: "Inline Dropdown",
          disabled: true
        }
      },
      %Variation{
        id: :large_items,
        attributes: %{
          label: "Inline Dropdown with large items"
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
        description: "Inline dropdown with icon",
        attributes: %{
          label: "Options"
        },
        slots: [
          """
          <:icon><.category /></:icon>
          <.dropdown_item value="1" label="Item 1"/>
          <.dropdown_item value="2" label="Item 2"/>
          <.dropdown_item value="3" label="Item 3"/>
          """
        ]
      },
      %Variation{
        id: :with_secondary_text,
        description: "Inline dropdown with secondary_text in items",
        attributes: %{
          label: "Options"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Item 1" secondary_text="Foo"/>
          <.dropdown_item value="2" label="Item 2" secondary_text="Bar"/>
          <.dropdown_item value="3" label="Item 3" secondary_text="Baz"/>
          """
        ]
      }
    ]
  end
end