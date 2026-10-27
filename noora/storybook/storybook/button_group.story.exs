defmodule TuistWeb.Storybook.ButtonGroup do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.ButtonGroup

  def imports, do: [{ButtonGroup, [button_group_item: 1]}, {Noora.Icon, chevron_left: 1, chevron_right: 1}]

  def function, do: &ButtonGroup.button_group/1

  def variations do
    [
      %VariationGroup{
        id: :sizes,
        description: "Button group sizes from small to large",
        variations: [
          %Variation{
            id: :small,
            attributes: %{
              id: "button-group-small",
              size: "small"
            },
            slots: [
              """
              <.button_group_item label="First" />
              <.button_group_item label="Second" />
              <.button_group_item label="Third" />
              """
            ]
          },
          %Variation{
            id: :medium,
            attributes: %{
              id: "button-group-medium",
              size: "medium"
            },
            slots: [
              """
              <.button_group_item label="First" />
              <.button_group_item label="Second" />
              <.button_group_item label="Third" />
              """
            ]
          },
          %Variation{
            id: :large,
            attributes: %{
              id: "button-group-large",
              size: "large"
            },
            slots: [
              """
              <.button_group_item label="First" />
              <.button_group_item label="Second" />
              <.button_group_item label="Third" />
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :icon_configurations,
        description: "Different icon arrangements and combinations",
        variations: [
          %Variation{
            id: :with_icons,
            attributes: %{
              id: "button-group-icons",
              size: "medium"
            },
            slots: [
              """
              <.button_group_item label="Previous">
                <:icon_left><.chevron_left /></:icon_left>
              </.button_group_item>
              <.button_group_item label="Both">
                <:icon_left><.chevron_left /></:icon_left>
                <:icon_right><.chevron_right /></:icon_right>
              </.button_group_item>
              <.button_group_item label="Next">
                <:icon_right><.chevron_right /></:icon_right>
              </.button_group_item>
              """
            ]
          },
          %Variation{
            id: :icon_only,
            attributes: %{
              id: "button-group-icon-only",
              size: "medium"
            },
            slots: [
              """
              <.button_group_item icon_only>
                <.chevron_left />
              </.button_group_item>
              <.button_group_item icon_only>
                <.chevron_right />
              </.button_group_item>
              """
            ]
          },
          %Variation{
            id: :mixed_icons,
            attributes: %{
              id: "button-group-mixed",
              size: "medium"
            },
            slots: [
              """
              <.button_group_item icon_only>
                <.chevron_left />
              </.button_group_item>
              <.button_group_item label="Page 1" />
              <.button_group_item label="Page 2" />
              <.button_group_item icon_only>
                <.chevron_right />
              </.button_group_item>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :states,
        description: "Different button states within groups",
        variations: [
          %Variation{
            id: :with_disabled,
            attributes: %{
              id: "button-group-disabled",
              size: "medium"
            },
            slots: [
              """
              <.button_group_item label="Available" />
              <.button_group_item label="Disabled" disabled />
              <.button_group_item label="Available" />
              """
            ]
          },
          %Variation{
            id: :all_disabled,
            attributes: %{
              id: "button-group-all-disabled",
              size: "medium"
            },
            slots: [
              """
              <.button_group_item label="First" disabled />
              <.button_group_item label="Second" disabled />
              <.button_group_item label="Third" disabled />
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :practical_examples,
        description: "Real-world button group usage examples",
        variations: [
          %Variation{
            id: :pagination_controls,
            attributes: %{
              id: "button-group-pagination",
              size: "medium"
            },
            slots: [
              """
              <.button_group_item icon_only>
                <.chevron_left />
              </.button_group_item>
              <.button_group_item label="1" />
              <.button_group_item label="2" />
              <.button_group_item label="3" />
              <.button_group_item icon_only>
                <.chevron_right />
              </.button_group_item>
              """
            ]
          },
          %Variation{
            id: :view_toggle,
            attributes: %{
              id: "button-group-view-toggle",
              size: "small"
            },
            slots: [
              """
              <.button_group_item label="List" />
              <.button_group_item label="Grid" />
              <.button_group_item label="Card" />
              """
            ]
          }
        ]
      }
    ]
  end
end
