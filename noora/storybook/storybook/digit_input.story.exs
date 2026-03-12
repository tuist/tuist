defmodule TuistWeb.Storybook.DigitInput do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.TextInput.digit_input/1

  def variations do
    [
      %VariationGroup{
        id: :types,
        description: "Different input types for various validation patterns",
        variations: [
          %Variation{
            id: :numeric,
            attributes: %{
              id: "digit-input-numeric",
              type: "numeric",
              characters: 6,
              placeholder: "•"
            }
          },
          %Variation{
            id: :alphanumeric,
            attributes: %{
              id: "digit-input-alphanumeric",
              type: "alphanumeric",
              characters: 4,
              placeholder: "•"
            }
          },
          %Variation{
            id: :alphabetic,
            attributes: %{
              id: "digit-input-alphabetic",
              type: "alphabetic",
              characters: 3,
              placeholder: "•"
            }
          }
        ]
      },
      %VariationGroup{
        id: :character_counts,
        description: "Different character lengths for various use cases",
        variations: [
          %Variation{
            id: :short_code,
            attributes: %{
              id: "digit-input-short",
              type: "numeric",
              characters: 4,
              placeholder: "•"
            }
          },
          %Variation{
            id: :medium_code,
            attributes: %{
              id: "digit-input-medium",
              type: "numeric",
              characters: 6,
              placeholder: "•"
            }
          },
          %Variation{
            id: :long_code,
            attributes: %{
              id: "digit-input-long",
              type: "numeric",
              characters: 8,
              placeholder: "•"
            }
          }
        ]
      },
      %VariationGroup{
        id: :otp,
        description: "One-time password specific configurations",
        variations: [
          %Variation{
            id: :otp_enabled,
            attributes: %{
              id: "digit-input-otp",
              type: "numeric",
              characters: 6,
              otp: true,
              placeholder: "•"
            }
          },
          %Variation{
            id: :otp_sms_code,
            attributes: %{
              id: "digit-input-sms",
              type: "numeric",
              characters: 4,
              otp: true,
              placeholder: "0"
            }
          }
        ]
      },
      %VariationGroup{
        id: :states,
        description: "Different input states and error conditions",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "digit-input-default",
              type: "numeric",
              characters: 4,
              placeholder: "•"
            }
          },
          %Variation{
            id: :disabled,
            attributes: %{
              id: "digit-input-disabled",
              type: "numeric",
              characters: 4,
              disabled: true,
              placeholder: "•"
            }
          },
          %Variation{
            id: :error,
            attributes: %{
              id: "digit-input-error",
              type: "numeric",
              characters: 4,
              error: true,
              placeholder: "•"
            }
          }
        ]
      },
      %VariationGroup{
        id: :placeholders,
        description: "Different placeholder styles",
        variations: [
          %Variation{
            id: :dot_placeholder,
            attributes: %{
              id: "digit-input-dot",
              type: "numeric",
              characters: 6,
              placeholder: "•"
            }
          },
          %Variation{
            id: :dash_placeholder,
            attributes: %{
              id: "digit-input-dash",
              type: "numeric",
              characters: 6,
              placeholder: "-"
            }
          },
          %Variation{
            id: :no_placeholder,
            attributes: %{
              id: "digit-input-no-placeholder",
              type: "numeric",
              characters: 6
            }
          }
        ]
      }
    ]
  end
end
