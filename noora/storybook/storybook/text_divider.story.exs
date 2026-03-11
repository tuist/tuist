defmodule TuistWeb.Storybook.TextDivider do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.TextDivider.text_divider/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic text divider variations with different text content",
        variations: [
          %Variation{
            id: :or,
            attributes: %{
              id: "text-divider-or",
              text: "OR"
            }
          },
          %Variation{
            id: :and,
            attributes: %{
              id: "text-divider-and",
              text: "AND"
            }
          },
          %Variation{
            id: :section,
            attributes: %{
              id: "text-divider-section",
              text: "Section 2"
            }
          }
        ]
      },
      %VariationGroup{
        id: :content_types,
        description: "Different types of divider text content",
        variations: [
          %Variation{
            id: :short_text,
            attributes: %{
              id: "text-divider-short",
              text: "•"
            }
          },
          %Variation{
            id: :numeric,
            attributes: %{
              id: "text-divider-numeric",
              text: "1"
            }
          },
          %Variation{
            id: :long_text,
            attributes: %{
              id: "text-divider-long",
              text: "Alternative Options"
            }
          },
          %Variation{
            id: :date,
            attributes: %{
              id: "text-divider-date",
              text: "January 2024"
            }
          }
        ]
      }
    ]
  end
end
