defmodule TuistWeb.Storybook.NeutralButton do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Button.neutral_button/1
  def imports, do: [{TuistWeb.Noora.Icon, chevron_right: 1}]

  def variations do
    [
      %Variation{
        id: :neutral_button_large,
        attributes: %{
          size: "large"
        },
        slots: [
          """
          <.chevron_right />
          """
        ]
      },
      %Variation{
        id: :neutral_button_large_disabled,
        attributes: %{
          size: "large",
          disabled: true
        },
        slots: [
          """
          <.chevron_right />
          """
        ]
      },
      %Variation{
        id: :neutral_button_medium,
        attributes: %{
          size: "medium"
        },
        slots: [
          """
          <.chevron_right />
          """
        ]
      },
      %Variation{
        id: :neutral_button_small,
        attributes: %{
          size: "small"
        },
        slots: [
          """
          <.chevron_right />
          """
        ]
      }
    ]
  end
end
