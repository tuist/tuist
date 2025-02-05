defmodule TuistWeb.Storybook.DismissIcon do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.DismissIcon.dismiss_icon/1

  def variations do
    [
      %Variation{
        id: :large,
        attributes: %{
          size: "large"
        }
      },
      %Variation{
        id: :small,
        attributes: %{
          size: "small"
        }
      }
    ]
  end
end
