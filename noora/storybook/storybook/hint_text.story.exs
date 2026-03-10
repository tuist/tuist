defmodule TuistWeb.Storybook.HintText do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.HintText.hint_text/1

  def variations do
    [
      %VariationGroup{
        id: :variants,
        description: "Different hint text variants for various contexts",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "hint-text-default",
              label: "This is helpful hint text"
            }
          },
          %Variation{
            id: :destructive,
            attributes: %{
              id: "hint-text-destructive",
              label: "This field has an error that needs attention",
              variant: "destructive"
            }
          },
          %Variation{
            id: :disabled,
            attributes: %{
              id: "hint-text-disabled",
              label: "This field is currently disabled",
              variant: "disabled"
            }
          }
        ]
      },
      %VariationGroup{
        id: :content_examples,
        description: "Different types of hint text content",
        variations: [
          %Variation{
            id: :short_hint,
            attributes: %{
              id: "hint-text-short",
              label: "Required field"
            }
          },
          %Variation{
            id: :instructional,
            attributes: %{
              id: "hint-text-instructional",
              label: "Enter your email address to receive notifications"
            }
          },
          %Variation{
            id: :validation_help,
            attributes: %{
              id: "hint-text-validation",
              label: "Password must be at least 8 characters with one uppercase letter",
              variant: "destructive"
            }
          },
          %Variation{
            id: :long_hint,
            attributes: %{
              id: "hint-text-long",
              label: "This is a longer hint text that provides detailed information about what the user should enter in the associated field and why it's important for their account setup"
            }
          }
        ]
      }
    ]
  end
end
