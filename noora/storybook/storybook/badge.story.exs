defmodule TuistWeb.Storybook.Badge do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Badge.badge/1
  def imports, do: [{Noora.Icon, alert_circle: 1}]

  def variations do
    [
      %VariationGroup{
        id: "Fill",
        description: "Solid fill style badges with various colors",
        variations: color_variations("fill")
      },
      %VariationGroup{
        id: "Light fill",
        description: "Light fill style badges with subtle background colors",
        variations: color_variations("light-fill")
      },
      %VariationGroup{
        id: "size",
        description: "Badge sizes: small (default) and large",
        variations: size_variations()
      },
      %VariationGroup{
        id: "disabled",
        description: "Disabled state badge (overrides color)",
        variations: [
          %Variation{
            id: :disabled,
            attributes: %{
              id: "badge-disabled",
              disabled: true,
              label: "Disabled"
            }
          }
        ]
      },
      %VariationGroup{
        id: "dot",
        description: "Badges with dot indicators",
        variations: [
          %Variation{
            id: :dot,
            attributes: %{
              id: "badge-dot-small",
              dot: true,
              label: "Dot"
            }
          },
          %Variation{
            id: :dot_large,
            attributes: %{
              id: "badge-dot-large",
              dot: true,
              size: "large",
              label: "Dot"
            }
          }
        ]
      },
      %VariationGroup{
        id: "icon",
        description: "Badges with custom icons",
        variations: [
          %Variation{
            id: :icon,
            attributes: %{
              id: "badge-icon-small",
              label: "Icon"
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """
            ]
          },
          %Variation{
            id: :icon_large,
            attributes: %{
              id: "badge-icon-large",
              size: "large",
              label: "Icon"
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: "icon_only",
        description: "Icon only badges",
        variations: [
          %Variation{
            id: :icon_only_small,
            attributes: %{
              id: "badge-icon-only-small",
              icon_only: true
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """
            ]
          },
          %Variation{
            id: :icon_only_large,
            attributes: %{
              id: "badge-icon-only-large",
              size: "large",
              icon_only: true
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """
            ]
          },
          %Variation{
            id: :icon_only_colored,
            attributes: %{
              id: "badge-icon-only-colored",
              icon_only: true,
              color: "success",
              style: "light-fill"
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: "edge_cases",
        description: "Edge cases and special scenarios",
        variations: [
          %Variation{
            id: :long_label,
            attributes: %{
              id: "badge-edge-long-label",
              label: "Very Long Badge Label That Might Wrap"
            }
          },
          %Variation{
            id: :disabled_with_icon,
            attributes: %{
              id: "badge-edge-disabled-icon",
              disabled: true,
              label: "Disabled with Icon"
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """
            ]
          },
          %Variation{
            id: :colored_with_dot,
            attributes: %{
              id: "badge-edge-colored-dot",
              color: "success",
              style: "light-fill",
              dot: true,
              label: "Success with Dot"
            }
          }
        ]
      }
    ]
  end

  defp color_variations(appearance) do
    appearance_id = String.replace(appearance, "-", "_")

    Enum.map(Noora.Badge.badge_colors(), fn color ->
      %Variation{
        id: String.to_atom("#{appearance_id}_#{color}"),
        attributes: %{
          id: "badge-#{appearance}-#{color}",
          style: appearance,
          color: color,
          label: color
        }
      }
    end)
  end

  defp size_variations do
    Enum.map(Noora.Badge.badge_sizes(), fn size ->
      %Variation{
        id: String.to_atom("size_#{size}"),
        attributes: %{
          id: "badge-size-#{size}",
          size: size,
          label: String.capitalize(size)
        }
      }
    end)
  end
end
