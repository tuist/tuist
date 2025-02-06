defmodule TuistWeb.Storybook.DigitInput do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.TextInput.digit_input/1

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          characters: 3,
          on_complete: "foo"
        }
      },
      %Variation{
        id: :disabled,
        attributes: %{
          characters: 3,
          disabled: true
        }
      },
      %Variation{
        id: :error,
        attributes: %{
          characters: 3,
          error: true
        }
      }
    ]
  end
end
