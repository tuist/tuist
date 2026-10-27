defmodule TuistWeb.Storybook.TextArea do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.TextArea.text_area/1

  def variations do
    [
      %Variation{
        id: :basic,
        attributes: %{
          name: "basic",
          placeholder: "Enter your message...",
          max_length: 200
        }
      },
      %Variation{
        id: :required,
        attributes: %{
          name: "required",
          label: "Message",
          placeholder: "This field is required",
          required: true,
          show_required: true
        }
      },
      %Variation{
        id: :with_hint,
        attributes: %{
          name: "with_hint",
          label: "Feedback",
          placeholder: "Share your feedback...",
          hint: "Please be as detailed as possible"
        }
      },
      %Variation{
        id: :error,
        attributes: %{
          name: "error",
          label: "Message",
          placeholder: "Enter your message...",
          error: "This field is required",
          value: ""
        }
      },
      %Variation{
        id: :disabled,
        attributes: %{
          name: "disabled",
          label: "Disabled",
          placeholder: "Enter your message...",
          disabled: true
        }
      },
    ]
  end
end
