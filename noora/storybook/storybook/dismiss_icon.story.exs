defmodule TuistWeb.Storybook.DismissIcon do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.DismissIcon.dismiss_icon/1

  def variations do
    [
      %VariationGroup{
        id: :sizes,
        description: "Different sizes for various UI contexts",
        variations: [
          %Variation{
            id: :small,
            attributes: %{
              id: "dismiss-icon-small",
              size: "small"
            }
          },
          %Variation{
            id: :large,
            attributes: %{
              id: "dismiss-icon-large", 
              size: "large"
            }
          }
        ]
      },
      %VariationGroup{
        id: :states,
        description: "Different interaction states",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "dismiss-icon-default",
              size: "large"
            }
          },
          %Variation{
            id: :disabled,
            attributes: %{
              id: "dismiss-icon-disabled",
              size: "large",
              disabled: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :with_events,
        description: "Dismiss icons with event handlers",
        variations: [
          %Variation{
            id: :with_event,
            attributes: %{
              id: "dismiss-icon-with-event",
              size: "large",
              on_dismiss: "close-modal"
            }
          },
          %Variation{
            id: :small_with_event,
            attributes: %{
              id: "dismiss-icon-small-event",
              size: "small",
              on_dismiss: "close-alert"
            }
          }
        ]
      }
    ]
  end
end
