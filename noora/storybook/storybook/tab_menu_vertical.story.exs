defmodule TuistWeb.Storybook.TabMenuVertical do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.TabMenu.tab_menu_vertical/1
  def imports, do: [{Noora.Icon, [category: 1]}]

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic vertical tab menu item variations",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "tab-vertical-default",
              label: "Dashboard"
            }
          },
          %Variation{
            id: :with_left_icon,
            attributes: %{
              id: "tab-vertical-left-icon",
              label: "Analytics"
            },
            slots: [
              """
              <:icon_left>
                <.category />
              </:icon_left>
              """
            ]
          },
          %Variation{
            id: :with_right_icon,
            attributes: %{
              id: "tab-vertical-right-icon",
              label: "Settings"
            },
            slots: [
              """
              <:icon_right>
                <.category />
              </:icon_right>
              """
            ]
          },
          %Variation{
            id: :with_both_icons,
            attributes: %{
              id: "tab-vertical-both-icons",
              label: "Users"
            },
            slots: [
              """
              <:icon_left>
                <.category />
              </:icon_left>
              <:icon_right>
                <.category />
              </:icon_right>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Edge cases and special scenarios",
        variations: [
          %Variation{
            id: :long_label,
            attributes: %{
              id: "tab-vertical-long-label",
              label: "Very Long Tab Label That Might Wrap"
            }
          },
          %Variation{
            id: :short_label,
            attributes: %{
              id: "tab-vertical-short",
              label: "A"
            }
          }
        ]
      }
    ]
  end
end
