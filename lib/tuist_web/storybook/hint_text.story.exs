defmodule TuistWeb.Storybook.HintText do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.HintText.hint_text/1

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          label: "This is a hint text"
        }
      },
      %Variation{
        id: :destructive,
        attributes: %{
          label: "This is a hint text",
          variant: "destructive"
        }
      },
      %Variation{
        id: :disabled,
        attributes: %{
          label: "This is a hint text",
          variant: "disabled"
        }
      }
    ]
  end
end
