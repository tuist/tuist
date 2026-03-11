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
          selected_preset: "7d"
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
