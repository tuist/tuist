defmodule TuistWeb.Storybook.GhostButton do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Button.ghost_button/1
  def imports, do: [{Noora.Icon, chevron_right: 1, chevron_left: 1}]

  def variations do
    [
      %VariationGroup{
        id: :sizes,
        description: "Ghost button sizes from small to large",
        variations: [
          %Variation{
            id: :small,
            attributes: %{
              id: "ghost-button-small",
              size: "small"
            },
            slots: [
              """
              <.chevron_right />
              """
            ]
          },
          %Variation{
            id: :medium,
            attributes: %{
              id: "ghost-button-medium",
              size: "medium"
            },
            slots: [
              """
              <.chevron_right />
              """
            ]
          },
          %Variation{
            id: :large,
            attributes: %{
              id: "ghost-button-large",
              size: "large"
            },
            slots: [
              """
              <.chevron_right />
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :states,
        description: "Different button states",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "ghost-button-default",
              size: "medium"
            },
            slots: [
              """
              <.chevron_right />
              """
            ]
          },
          %Variation{
            id: :disabled,
            attributes: %{
              id: "ghost-button-disabled",
              size: "medium",
              disabled: true
            },
            slots: [
              """
              <.chevron_right />
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :text_sizes,
        description: "Text labels from small to large",
        variations: [
          %Variation{
            id: :text_small,
            attributes: %{
              id: "ghost-button-text-small",
              size: "small",
              label: "Button"
            }
          },
          %Variation{
            id: :text_medium,
            attributes: %{
              id: "ghost-button-text-medium",
              size: "medium",
              label: "Button"
            }
          },
          %Variation{
            id: :text_large,
            attributes: %{
              id: "ghost-button-text-large",
              size: "large",
              label: "Button"
            }
          }
        ]
      },
      %VariationGroup{
        id: :text_states,
        description: "Text label states and icons",
        variations: [
          %Variation{
            id: :text_with_icons,
            attributes: %{
              id: "ghost-button-text-with-icons",
              size: "large",
              label: "Button"
            },
            slots: [
              """
              <:icon_left><.chevron_left /></:icon_left>
              """,
              """
              <:icon_right><.chevron_right /></:icon_right>
              """
            ]
          },
          %Variation{
            id: :text_disabled,
            attributes: %{
              id: "ghost-button-text-disabled",
              size: "large",
              label: "Button",
              disabled: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :different_icons,
        description: "Ghost buttons with various icon types",
        variations: [
          %Variation{
            id: :chevron_left,
            attributes: %{
              id: "ghost-button-chevron-left",
              size: "medium"
            },
            slots: [
              """
              <.chevron_left />
              """
            ]
          },
          %Variation{
            id: :chevron_right,
            attributes: %{
              id: "ghost-button-chevron-right",
              size: "medium"
            },
            slots: [
              """
              <.chevron_right />
              """
            ]
          }
        ]
      }
    ]
  end
end
