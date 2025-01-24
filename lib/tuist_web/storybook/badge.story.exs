defmodule TuistWeb.Storybook.Badge do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Badge.badge/1
  def imports, do: [{TuistWeb.Noora.Icon, alert_circle: 1}]

  def variations do
    [
      %VariationGroup{
        id: "Fill",
        description: "Fill",
        variations: [
          %Variation{
            id: :fill_neutral,
            attributes: %{
              style: "fill",
              color: "neutral",
              label: "neutral"
            }
          },
          %Variation{
            id: :fill_destructive,
            attributes: %{style: "fill", color: "destructive", label: "destructive"}
          },
          %Variation{
            id: :fill_warning,
            attributes: %{style: "fill", color: "warning", label: "warning"}
          },
          %Variation{
            id: :fill_attention,
            attributes: %{style: "fill", color: "attention", label: "attention"}
          },
          %Variation{
            id: :fill_success,
            attributes: %{style: "fill", color: "success", label: "success"}
          },
          %Variation{
            id: :fill_information,
            attributes: %{style: "fill", color: "information", label: "information"}
          },
          %Variation{
            id: :fill_focus,
            attributes: %{style: "fill", color: "focus", label: "focus"}
          },
          %Variation{
            id: :fill_primary,
            attributes: %{style: "fill", color: "primary", label: "primary"}
          },
          %Variation{
            id: :fill_secondary,
            attributes: %{style: "fill", color: "secondary", label: "secondary"}
          }
        ]
      },
      %VariationGroup{
        id: "Light fill",
        description: "Light fill",
        variations: [
          %Variation{
            id: :light_fill_neutral,
            attributes: %{style: "light-fill", color: "neutral", label: "neutral"}
          },
          %Variation{
            id: :light_fill_destructive,
            attributes: %{style: "light-fill", color: "destructive", label: "destructive"}
          },
          %Variation{
            id: :light_fill_warning,
            attributes: %{style: "light-fill", color: "warning", label: "warning"}
          },
          %Variation{
            id: :light_fill_attention,
            attributes: %{style: "light-fill", color: "attention", label: "attention"}
          },
          %Variation{
            id: :light_fill_success,
            attributes: %{style: "light-fill", color: "success", label: "success"}
          },
          %Variation{
            id: :light_fill_information,
            attributes: %{style: "light-fill", color: "information", label: "information"}
          },
          %Variation{
            id: :light_fill_focus,
            attributes: %{style: "light-fill", color: "focus", label: "focus"}
          },
          %Variation{
            id: :light_fill_primary,
            attributes: %{style: "light-fill", color: "primary", label: "primary"}
          },
          %Variation{
            id: :light_fill_secondary,
            attributes: %{style: "light-fill", color: "secondary", label: "secondary"}
          }
        ]
      },
      %VariationGroup{
        id: "size",
        description: "Size",
        variations: [
          %Variation{
            id: :size_small,
            attributes: %{
              size: "small",
              label: "Small"
            }
          },
          %Variation{
            id: :size_large,
            attributes: %{
              size: "large",
              label: "Large"
            }
          }
        ]
      },
      %VariationGroup{
        id: "disabled",
        description: "Disabled",
        variations: [
          %Variation{
            id: :disabled,
            attributes: %{
              disabled: true,
              label: "Disabled"
            }
          }
        ]
      },
      %VariationGroup{
        id: "dot",
        description: "Dot",
        variations: [
          %Variation{
            id: :dot,
            attributes: %{
              dot: true,
              label: "Dot"
            }
          },
          %Variation{
            id: :dot_large,
            attributes: %{
              dot: true,
              size: "large",
              label: "Dot"
            }
          }
        ]
      },
      %VariationGroup{
        id: "icon",
        description: "Icon",
        variations: [
          %Variation{
            id: :icon,
            attributes: %{
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
      }
    ]
  end
end
