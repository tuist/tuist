defmodule TuistWeb.Storybook.Button do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Button.button/1
  def imports, do: [{Noora.Icon, chevron_left: 1, chevron_right: 1}]

  def variations do
    variant_variations =
      Enum.map(Noora.Button.button_variants(), fn variant ->
        %Variation{
          id: String.to_atom("variant_#{variant}"),
          attributes: %{
            label: String.capitalize(variant),
            variant: variant
          }
        }
      end)

    size_variations =
      Noora.Button.button_sizes()
      |> Enum.reverse()
      |> Enum.map(fn size ->
        %Variation{
          id: String.to_atom("size_#{size}"),
          attributes: %{
            label: String.capitalize(size),
            size: size
          }
        }
      end)

    disabled_variations =
      Enum.map(Noora.Button.button_variants(), fn variant ->
        %Variation{
          id: String.to_atom("disabled_#{variant}"),
          attributes: %{
            label: "Disabled",
            variant: variant,
            disabled: true
          }
        }
      end)

    [
      %VariationGroup{
        id: :variant,
        description: "Variant",
        variations: variant_variations
      },
      %VariationGroup{
        id: :size,
        description: "Size",
        variations: size_variations
      },
      %VariationGroup{
        id: :disabled,
        description: "Disabled",
        variations: disabled_variations
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
