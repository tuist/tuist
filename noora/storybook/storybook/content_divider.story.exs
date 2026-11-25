defmodule TuistWeb.Storybook.ContentDivider do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.ContentDivider.content_divider/1

  def variations do
    [
      %VariationGroup{
        id: :line,
        description: "Line variant, with and without text",
        variations: [
          %Variation{
            id: :simple,
            attributes: %{
              id: "content-divider-simple"
            }
          },
          %Variation{
            id: :with_text,
            attributes: %{
              id: "content-divider-with-text",
              text: "OR"
            }
          },
          %Variation{
            id: :long_text,
            attributes: %{
              id: "content-divider-long",
              text: "Alternative method"
            }
          }
        ]
      },
      %VariationGroup{
        id: :text,
        description: "Text variant: a label without a line",
        variations: [
          %Variation{
            id: :or,
            attributes: %{
              id: "content-divider-text-or",
              variant: "text",
              text: "OR"
            }
          },
          %Variation{
            id: :section,
            attributes: %{
              id: "content-divider-text-section",
              variant: "text",
              text: "Section 2"
            }
          },
          %Variation{
            id: :date,
            attributes: %{
              id: "content-divider-text-date",
              variant: "text",
              text: "January 2024"
            }
          }
        ]
      }
    ]
  end
end
