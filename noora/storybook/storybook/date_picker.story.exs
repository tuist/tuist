defmodule TuistWeb.Storybook.DatePicker do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.DatePicker

  def function, do: &DatePicker.date_picker/1

  def variations do
    [
      %Variation{
        id: :default,
        description: "Date picker with default presets",
        attributes: %{
          id: "date-picker-default",
          open: true,
          selected_preset: "7d",
          presets: [
            %{id: "1h", label: "Last 1 hour", period: {1, :hour}},
            %{id: "24h", label: "Last 24 hours", period: {24, :hour}},
            %{id: "7d", label: "Last 7 days", period: {7, :day}},
            %{id: "30d", label: "Last 30 days", period: {30, :day}},
            %{id: "custom", label: "Custom"}
          ]
        },
        slots: [
          """
          <:actions>
            <button
              type="button"
              class="noora-button"
              data-variant="secondary"
              data-size="medium"
              phx-click={JS.dispatch("phx:date-picker-cancel", detail: %{id: "date-picker-default"})}
            >
              Cancel
            </button>
            <button
              type="button"
              class="noora-button"
              data-variant="primary"
              data-size="medium"
              phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "date-picker-default"})}
            >
              Apply
            </button>
          </:actions>
          """
        ]
      }
    ]
  end
end
