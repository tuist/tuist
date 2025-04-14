defmodule TuistWeb.Storybook.ProgressBar do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.ProgressBar.progress_bar/1

  def variations do
    [
      %Variation{
        id: :progress_bar,
        attributes: %{
          value: 75,
          max: 200
        }
      },
      %Variation{
        id: :progress_bar_with_title,
        attributes: %{
          value: 75,
          max: 200,
          title: "Credits:"
        }
      }
    ]
  end
end
