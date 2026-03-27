defmodule TuistWeb.Storybook.Toggle do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Toggle.toggle/1

  def variations do
    [
      %VariationGroup{
        id: :basic_states,
        description: "Basic toggle states and interactions",
        variations: [
          %Variation{
            id: :off,
            attributes: %{
              id: "toggle-off",
              label: "Enable notifications"
            }
          },
          %Variation{
            id: :on,
            attributes: %{
              id: "toggle-on",
              label: "Email alerts",
              checked: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :disabled_states,
        description: "Disabled toggle variations",
        variations: [
          %Variation{
            id: :disabled_off,
            attributes: %{
              id: "toggle-disabled-off",
              label: "Disabled off",
              disabled: true
            }
          },
          %Variation{
            id: :disabled_on,
            attributes: %{
              id: "toggle-disabled-on",
              label: "Disabled on",
              disabled: true,
              checked: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :with_description,
        description: "Toggle with additional descriptive text",
        variations: [
          %Variation{
            id: :simple_description,
            attributes: %{
              id: "toggle-simple-description",
              label: "Marketing emails",
              description: "Receive updates about new features and promotions"
            }
          }
        ]
      }
    ]
  end
end
