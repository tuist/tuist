defmodule TuistWeb.Storybook.Checkbox do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Checkbox.checkbox/1

  def variations do
    [
      %VariationGroup{
        id: :basic_states,
        description: "Basic checkbox states and interactions",
        variations: [
          %Variation{
            id: :unchecked,
            attributes: %{
              id: "checkbox-unchecked",
              label: "Enable notifications"
            }
          },
          %Variation{
            id: :checked,
            attributes: %{
              id: "checkbox-checked",
              label: "Email alerts",
              checked: true
            }
          },
          %Variation{
            id: :indeterminate,
            attributes: %{
              id: "checkbox-indeterminate",
              label: "Select all items",
              indeterminate: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :disabled_states,
        description: "Disabled checkbox variations",
        variations: [
          %Variation{
            id: :disabled_unchecked,
            attributes: %{
              id: "checkbox-disabled-unchecked",
              label: "Disabled unchecked",
              disabled: true
            }
          },
          %Variation{
            id: :disabled_checked,
            attributes: %{
              id: "checkbox-disabled-checked",
              label: "Disabled checked",
              disabled: true,
              checked: true
            }
          },
          %Variation{
            id: :disabled_indeterminate,
            attributes: %{
              id: "checkbox-disabled-indeterminate",
              label: "Disabled indeterminate",
              disabled: true,
              indeterminate: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :with_descriptions,
        description: "Checkboxes with additional descriptive text",
        variations: [
          %Variation{
            id: :simple_description,
            attributes: %{
              id: "checkbox-simple-description",
              label: "Marketing emails",
              description: "Receive updates about new features and promotions"
            }
          },
          %Variation{
            id: :long_description,
            attributes: %{
              id: "checkbox-long-description",
              label: "Data sharing",
              description: "Allow us to share anonymized usage data with third-party analytics providers to improve our service quality and user experience"
            }
          },
          %Variation{
            id: :checked_with_description,
            attributes: %{
              id: "checkbox-checked-description",
              label: "Remember my preferences",
              description: "Save your settings for future visits",
              checked: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :practical_examples,
        description: "Real-world checkbox usage scenarios",
        variations: [
          %Variation{
            id: :terms_agreement,
            attributes: %{
              id: "checkbox-terms",
              label: "I agree to the Terms of Service",
              description: "By checking this box, you agree to our terms and conditions"
            }
          },
          %Variation{
            id: :newsletter_signup,
            attributes: %{
              id: "checkbox-newsletter",
              label: "Subscribe to our newsletter",
              description: "Get weekly updates delivered to your inbox"
            }
          },
          %Variation{
            id: :feature_toggle,
            attributes: %{
              id: "checkbox-feature-toggle",
              label: "Enable dark mode",
              description: "Switch to a darker color scheme",
              checked: true
            }
          }
        ]
      }
    ]
  end
end
