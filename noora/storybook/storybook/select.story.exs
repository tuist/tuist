defmodule TuistWeb.Storybook.Select do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Select

  def function, do: &Select.select/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic select configurations",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "select-country",
              label: "Country",
              name: "country"
            },
            slots: [country_items()]
          },
          %Variation{
            id: :selected,
            attributes: %{
              id: "select-country-selected",
              label: "Country",
              name: "country",
              value: "de"
            },
            slots: [country_items()]
          }
        ]
      },
      %VariationGroup{
        id: :content,
        description: "Select options with supporting content",
        variations: [
          %Variation{
            id: :icons,
            attributes: %{
              id: "select-workspace",
              label: "Workspace",
              name: "workspace",
              value: "application"
            },
            slots: [
              """
              <:item value="application" label="Application" icon="category" />
              <:item value="framework" label="Framework" icon="category" />
              <:item value="package" label="Package" icon="category" />
              """
            ]
          },
          %Variation{
            id: :hint,
            attributes: %{
              id: "select-country-hint",
              label: "Country",
              name: "country",
              hint: "Used for regional settings."
            },
            slots: [country_items()]
          }
        ]
      },
      %VariationGroup{
        id: :states,
        description: "Select states",
        variations: [
          %Variation{
            id: :disabled,
            attributes: %{
              id: "select-country-disabled",
              label: "Country",
              name: "country",
              value: "de",
              disabled: true
            },
            slots: [country_items()]
          }
        ]
      }
    ]
  end

  defp country_items do
    """
    <:item value="es" label="Spain" />
    <:item value="de" label="Germany" />
    <:item value="fr" label="France" />
    """
  end
end
