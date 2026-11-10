defmodule TuistWeb.Storybook.Label do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Label.label/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic label variations with different configurations",
        variations: [
          %Variation{
            id: :simple,
            attributes: %{
              id: "label-simple",
              label: "Email Address"
            }
          },
          %Variation{
            id: :required,
            attributes: %{
              id: "label-required",
              label: "Password",
              required: true
            }
          },
          %Variation{
            id: :with_sublabel,
            attributes: %{
              id: "label-with-sublabel",
              label: "Full Name",
              sublabel: "(First and last name)"
            }
          },
          %Variation{
            id: :required_with_sublabel,
            attributes: %{
              id: "label-required-sublabel",
              label: "Company Email",
              required: true,
              sublabel: "(Must be a work email address)"
            }
          },
          %Variation{
            id: :with_tooltip,
            attributes: %{
              id: "label-with-tooltip",
              label: "API access token",
              tooltip: "Lets merge request pipelines save cache volumes. Needs the read_api scope.",
              tooltip_id: "label-with-tooltip-help"
            }
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Edge cases and special label scenarios",
        variations: [
          %Variation{
            id: :long_label,
            attributes: %{
              id: "label-long",
              label: "Very Long Label That Might Wrap to Multiple Lines in Narrow Containers",
              required: true
            }
          },
          %Variation{
            id: :long_sublabel,
            attributes: %{
              id: "label-long-sublabel",
              label: "API Key",
              sublabel: "(This is a very long sublabel that provides detailed information about what this field should contain and how it will be used in the application)"
            }
          },
          %Variation{
            id: :short_label,
            attributes: %{
              id: "label-short",
              label: "ID",
              required: true
            }
          }
        ]
      }
    ]
  end
end
