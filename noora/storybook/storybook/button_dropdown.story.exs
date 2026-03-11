defmodule TuistWeb.Storybook.ButtonDropdown do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.ButtonDropdown

  def function, do: &ButtonDropdown.button_dropdown/1

  def imports,
    do: [{Noora.Dropdown, [dropdown_item: 1]}, {Noora.Icon, [chevron_left: 1, chevron_right: 1]}]

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          id: "button-dropdown-default",
          label: "Button"
        },
        slots: [
          """
          <.dropdown_item value="1" label="Option 1" />
          <.dropdown_item value="2" label="Option 2" />
          <.dropdown_item value="3" label="Option 3" />
          """
        ]
      },
      %VariationGroup{
        id: :sizes,
        description: "Sizes",
        variations: [
          %Variation{
            id: :medium,
            attributes: %{
              id: "button-dropdown-medium",
              label: "Button",
              size: "medium"
            },
            slots: [
              """
              <.dropdown_item value="1" label="Option 1" />
              <.dropdown_item value="2" label="Option 2" />
              """
            ]
          },
          %Variation{
            id: :large,
            attributes: %{
              id: "button-dropdown-large",
              label: "Button",
              size: "large"
            },
            slots: [
              """
              <.dropdown_item value="1" label="Option 1" />
              <.dropdown_item value="2" label="Option 2" />
              """
            ]
          }
        ]
      },
      %Variation{
        id: :with_icons,
        description: "With icons",
        attributes: %{
          id: "button-dropdown-icons",
          label: "Button"
        },
        slots: [
          """
          <:icon_left><.chevron_left /></:icon_left>
          <:icon_right><.chevron_right /></:icon_right>
          <.dropdown_item value="1" label="Option 1" />
          <.dropdown_item value="2" label="Option 2" />
          """
        ]
      },
      %Variation{
        id: :disabled,
        description: "Disabled",
        attributes: %{
          id: "button-dropdown-disabled",
          label: "Button",
          disabled: true
        },
        slots: [
          """
          <.dropdown_item value="1" label="Option 1" />
          <.dropdown_item value="2" label="Option 2" />
          """
        ]
      }
    ]
  end
end
