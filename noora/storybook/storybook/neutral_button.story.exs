defmodule TuistWeb.Storybook.NeutralButton do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Button.neutral_button/1
  def imports, do: [{Noora.Icon, chevron_right: 1, chevron_left: 1}]

  def variations do
    [
      %VariationGroup{
        id: :sizes,
        description: "Neutral button sizes from small to large",
        variations: [
          %Variation{
            id: :small,
            attributes: %{
              id: "neutral-button-small",
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
              id: "neutral-button-medium",
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
              id: "neutral-button-large",
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
              id: "neutral-button-default",
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
              id: "neutral-button-disabled",
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
        id: :different_icons,
        description: "Neutral buttons with various icon types",
        variations: [
          %Variation{
            id: :chevron_left,
            attributes: %{
              id: "neutral-button-chevron-left",
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
              id: "neutral-button-chevron-right",
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
