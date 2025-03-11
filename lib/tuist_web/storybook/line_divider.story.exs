defmodule TuistWeb.Storybook.LineDivider do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.LineDivider.line_divider/1

  def variations do
    [
      %Variation{
        id: :line_divider
      },
      %Variation{
        id: :line_divider_with_text,
        attributes: %{
          text: "OR"
        }
      }
    ]
  end
end
