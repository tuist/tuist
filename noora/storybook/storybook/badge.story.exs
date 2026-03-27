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
        variations: [
          %Variation{
            id: :fill_neutral,
            attributes: %{
              id: "badge-fill-neutral",
              style: "fill",
              color: "neutral",
              label: "neutral"
            }
          },
          %Variation{
            id: :fill_destructive,
            attributes: %{id: "badge-fill-destructive", style: "fill", color: "destructive", label: "destructive"}
          },
          %Variation{
            id: :fill_warning,
            attributes: %{id: "badge-fill-warning", style: "fill", color: "warning", label: "warning"}
          },
          %Variation{
            id: :fill_attention,
            attributes: %{id: "badge-fill-attention", style: "fill", color: "attention", label: "attention"}
          },
          %Variation{
            id: :fill_success,
            attributes: %{id: "badge-fill-success", style: "fill", color: "success", label: "success"}
          },
          %Variation{
            id: :fill_information,
            attributes: %{id: "badge-fill-information", style: "fill", color: "information", label: "information"}
          },
          %Variation{
            id: :fill_focus,
            attributes: %{id: "badge-fill-focus", style: "fill", color: "focus", label: "focus"}
          },
          %Variation{
            id: :fill_primary,
            attributes: %{id: "badge-fill-primary", style: "fill", color: "primary", label: "primary"}
          },
          %Variation{
            id: :fill_secondary,
            attributes: %{id: "badge-fill-secondary", style: "fill", color: "secondary", label: "secondary"}
          }
        ]
      },
      %VariationGroup{
        id: "Light fill",
        description: "Light fill style badges with subtle background colors",
        variations: [
          %Variation{
            id: :light_fill_neutral,
            attributes: %{id: "badge-light-fill-neutral", style: "light-fill", color: "neutral", label: "neutral"}
          },
          %Variation{
            id: :light_fill_destructive,
            attributes: %{id: "badge-light-fill-destructive", style: "light-fill", color: "destructive", label: "destructive"}
          },
          %Variation{
            id: :light_fill_warning,
            attributes: %{id: "badge-light-fill-warning", style: "light-fill", color: "warning", label: "warning"}
          },
          %Variation{
            id: :light_fill_attention,
            attributes: %{id: "badge-light-fill-attention", style: "light-fill", color: "attention", label: "attention"}
          },
          %Variation{
            id: :light_fill_success,
            attributes: %{id: "badge-light-fill-success", style: "light-fill", color: "success", label: "success"}
          },
          %Variation{
            id: :light_fill_information,
            attributes: %{id: "badge-light-fill-information", style: "light-fill", color: "information", label: "information"}
          },
          %Variation{
            id: :light_fill_focus,
            attributes: %{id: "badge-light-fill-focus", style: "light-fill", color: "focus", label: "focus"}
          },
          %Variation{
            id: :light_fill_primary,
            attributes: %{id: "badge-light-fill-primary", style: "light-fill", color: "primary", label: "primary"}
          },
          %Variation{
            id: :light_fill_secondary,
            attributes: %{id: "badge-light-fill-secondary", style: "light-fill", color: "secondary", label: "secondary"}
          }
        ]
      },
      %VariationGroup{
        id: "size",
        description: "Badge sizes: small (default) and large",
        variations: [
          %Variation{
            id: :size_small,
            attributes: %{
              id: "badge-size-small",
              size: "small",
              label: "Small"
            }
          },
          %Variation{
            id: :size_large,
            attributes: %{
              id: "badge-size-large",
              size: "large",
              label: "Large"
            }
          }
        ]
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
              icon_only: true,
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
              icon_only: true,
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
              style: "light-fill",
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
end
