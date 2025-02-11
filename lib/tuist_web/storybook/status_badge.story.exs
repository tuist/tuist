defmodule TuistWeb.Storybook.StatusBadge do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Badge.status_badge/1

  def variations do
    [
      %VariationGroup{
        id: :icon,
        variations: [
          %Variation{
            id: :success,
            description: "Success",
            attributes: %{status: "success", label: "Success"}
          },
          %Variation{
            id: :error,
            description: "Error",
            attributes: %{status: "error", label: "Error"}
          },
          %Variation{
            id: :warning,
            description: "Warning",
            attributes: %{status: "warning", label: "Warning"}
          },
          %Variation{
            id: :disabled,
            description: "Disabled",
            attributes: %{status: "disabled", label: "Disabled"}
          }
        ]
      },
      %VariationGroup{
        id: :dot,
        variations: [
          %Variation{
            id: :success,
            description: "Success",
            attributes: %{type: "dot", status: "success", label: "Success"}
          },
          %Variation{
            id: :error,
            description: "Error",
            attributes: %{type: "dot", status: "error", label: "Error"}
          },
          %Variation{
            id: :warning,
            description: "Warning",
            attributes: %{type: "dot", status: "warning", label: "Warning"}
          },
          %Variation{
            id: :disabled,
            description: "Disabled",
            attributes: %{type: "dot", status: "disabled", label: "Disabled"}
          }
        ]
      }
    ]
  end
end
