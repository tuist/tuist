defmodule TuistWeb.Noora.Pages.DatePicker do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Date picker",
    description: "Selects a date range from presets or a calendar, such as the period an analytics chart covers.",
    components: [{Noora.DatePicker, :date_picker}],
    guidelines: [
      "Give each preset a `period` of `{amount, unit}`, where the unit is `:hour`, `:day`, `:week`, `:month`, or `:year`. The range ends now and starts that long ago.",
      "Add a preset with the id `custom` for ranges picked on the calendar. When it is selected and `period` is set, the trigger shows the dates instead of a preset label.",
      "Put Cancel and Apply buttons in the `:actions` slot. They dispatch `phx:date-picker-cancel` and `phx:date-picker-apply` with the picker's `id`.",
      "Applying sends `on_period_change` with the range's `start` and `end` as ISO 8601 strings under `value`, and the `preset` id. Store them and pass them back as `period` and `selected_preset`, with `period` as a tuple of two `DateTime` structs.",
      "Set `max` to today when there is no data for future dates, as in analytics."
    ]

  alias Phoenix.LiveView.JS

  example "Presets", description: "Presets list common ranges next to a two-month calendar.", layout: :column do
    ~H"""
    <.date_picker
      id="date-picker-presets"
      name="analytics-date-range"
      selected_preset="last-7-days"
      on_period_change="analytics_period_changed"
      presets={[
        %{id: "last-24-hours", label: "Last 24 hours", period: {24, :hour}},
        %{id: "last-7-days", label: "Last 7 days", period: {7, :day}},
        %{id: "last-30-days", label: "Last 30 days", period: {30, :day}},
        %{id: "last-12-months", label: "Last 12 months", period: {12, :month}},
        %{id: "custom", label: "Custom"}
      ]}
    >
      <:actions>
        <.button
          label="Cancel"
          variant="secondary"
          phx-click={JS.dispatch("phx:date-picker-cancel", detail: %{id: "date-picker-presets"})}
        />
        <.button
          label="Apply"
          phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "date-picker-presets"})}
        />
      </:actions>
    </.date_picker>
    """
  end

  example "Custom range",
    description: "With the `custom` preset and a `period`, the trigger shows the selected dates.",
    layout: :column do
    ~H"""
    <.date_picker
      id="date-picker-custom"
      name="analytics-date-range"
      selected_preset="custom"
      period={{~U[2026-09-01 00:00:00Z], ~U[2026-09-30 23:59:59Z]}}
      presets={[
        %{id: "last-7-days", label: "Last 7 days", period: {7, :day}},
        %{id: "last-30-days", label: "Last 30 days", period: {30, :day}},
        %{id: "custom", label: "Custom"}
      ]}
    >
      <:actions>
        <.button
          label="Cancel"
          variant="secondary"
          phx-click={JS.dispatch("phx:date-picker-cancel", detail: %{id: "date-picker-custom"})}
        />
        <.button
          label="Apply"
          phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "date-picker-custom"})}
        />
      </:actions>
    </.date_picker>
    """
  end

  example "Selectable range",
    description: "Days before `min` or after `max` can't be picked. `start_of_week` sets the first column.",
    layout: :column do
    ~H"""
    <.date_picker
      id="date-picker-limits"
      name="builds-date-range"
      label="Select a period"
      min={Date.add(Date.utc_today(), -90)}
      max={Date.utc_today()}
      start_of_week={1}
      presets={[
        %{id: "last-7-days", label: "Last 7 days", period: {7, :day}},
        %{id: "last-30-days", label: "Last 30 days", period: {30, :day}},
        %{id: "custom", label: "Custom"}
      ]}
    >
      <:actions>
        <.button
          label="Cancel"
          variant="secondary"
          phx-click={JS.dispatch("phx:date-picker-cancel", detail: %{id: "date-picker-limits"})}
        />
        <.button
          label="Apply"
          phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "date-picker-limits"})}
        />
      </:actions>
    </.date_picker>
    """
  end

  example "Disabled", layout: :column do
    ~H"""
    <.date_picker
      id="date-picker-disabled"
      name="analytics-date-range"
      selected_preset="last-30-days"
      disabled
      presets={[
        %{id: "last-7-days", label: "Last 7 days", period: {7, :day}},
        %{id: "last-30-days", label: "Last 30 days", period: {30, :day}},
        %{id: "custom", label: "Custom"}
      ]}
    />
    """
  end
end
