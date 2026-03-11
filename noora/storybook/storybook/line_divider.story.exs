defmodule TuistWeb.Storybook.LineDivider do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.LineDivider.line_divider/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic line divider variations with and without text",
        variations: [
          %Variation{
            id: :simple,
            attributes: %{
              id: "line-divider-simple"
            }
          },
          %Variation{
            id: :with_text,
            attributes: %{
              id: "line-divider-with-text",
              text: "OR"
            }
          }
        ]
      },
      %VariationGroup{
        id: :text_variations,
        description: "Different text content for dividers",
        variations: [
          %Variation{
            id: :and,
            attributes: %{
              id: "line-divider-and",
              text: "AND"
            }
          },
          %Variation{
            id: :continue,
            attributes: %{
              id: "line-divider-continue",
              text: "Continue with"
            }
          },
          %Variation{
            id: :numeric,
            attributes: %{
              id: "line-divider-numeric",
              text: "2"
            }
          },
          %Variation{
            id: :long_text,
            attributes: %{
              id: "line-divider-long",
              text: "Alternative method"
            }
          }
        ]
      }
    ]
  end
end
