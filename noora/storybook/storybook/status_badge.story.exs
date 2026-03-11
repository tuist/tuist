defmodule TuistWeb.Storybook.StatusBadge do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Badge.status_badge/1

  def variations do
    [
      %VariationGroup{
        id: :icon,
        description: "Status badges with type-specific icons",
        variations: [
          %Variation{
            id: :success,
            description: "Success",
            attributes: %{id: "status-badge-icon-success", status: "success", label: "Success"}
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
            id: :attention,
            description: "Attention",
            attributes: %{status: "attention", label: "Attention"}
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
        description: "Status badges with dot indicators instead of icons",
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
            id: :attention,
            description: "Attention",
            attributes: %{type: "dot", status: "attention", label: "Attention"}
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
