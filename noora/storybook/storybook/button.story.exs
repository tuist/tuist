defmodule TuistWeb.Storybook.Button do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Button.button/1
  def imports, do: [{Noora.Icon, chevron_left: 1, chevron_right: 1}]

  def variations do
    [
      %VariationGroup{
        id: :variant,
        description: "Variant",
        variations: [
          %Variation{
            id: :variant_primary,
            attributes: %{
              label: "Primary",
              variant: "primary"
            }
          },
          %Variation{
            id: :variant_secondary,
            attributes: %{
              label: "Secondary",
              variant: "secondary"
            }
          },
          %Variation{
            id: :variant_destructive,
            attributes: %{
              label: "Destructive",
              variant: "destructive"
            }
          }
        ]
      },
      %VariationGroup{
        id: :size,
        description: "Size",
        variations: [
          %Variation{
            id: :size_large,
            attributes: %{
              label: "Large",
              size: "large"
            }
          },
          %Variation{
            id: :size_medium,
            attributes: %{
              label: "Medium",
              size: "medium"
            }
          },
          %Variation{
            id: :size_small,
            attributes: %{
              label: "Small",
              size: "small"
            }
          }
        ]
      },
      %VariationGroup{
        id: :disabled,
        description: "Disabled",
        variations: [
          %Variation{
            id: :disabled_primary,
            attributes: %{
              label: "Disabled",
              variant: "primary",
              disabled: true
            }
          },
          %Variation{
            id: :disabled_secondary,
            attributes: %{
              label: "Disabled",
              variant: "secondary",
              disabled: true
            }
          },
          %Variation{
            id: :disabled_destructive,
            attributes: %{
              label: "Disabled",
              variant: "destructive",
              disabled: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :icon,
        description: "Icon",
        variations: [
          %Variation{
            id: :icon_left,
            attributes: %{
              label: "Icon",
              icon_position: "left"
            },
            slots: [
              """
              <:icon_left><.chevron_left /></:icon_left>
              """
            ]
          },
          %Variation{
            id: :icon_right,
            attributes: %{
              label: "Icon",
              icon_position: "right"
            },
            slots: [
              """
              <:icon_right><.chevron_right /></:icon_right>
              """
            ]
          },
          %Variation{
            id: :icon_both,
            attributes: %{
              label: "Icon",
              icon_position: "both"
            },
            slots: [
              """
              <:icon_left><.chevron_left /></:icon_left>
              <:icon_right><.chevron_right /></:icon_right>
              """
            ]
          },
          %Variation{
            id: :icon_only,
            attributes: %{
              icon_only: true
            },
            slots: [
              "<.chevron_left />"
            ]
          }
        ]
      }
    ]
  end
end
