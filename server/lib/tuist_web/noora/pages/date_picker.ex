defmodule TuistWeb.Noora.Pages.DatePicker do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Date picker",
    description: "Selects a date range from presets or a calendar, such as the period an analytics chart covers.",
    components: [{Noora.DatePicker, :date_picker}],
    guidelines: [
      "Give each preset a `period` of `{amount, unit}`, where the unit is `:hour`, `:day`, `:week`, `:month`, or `:year`. The range ends now and starts that long ago.",
      "Add a preset with the id `custom` for ranges picked on the calendar. When it is selected and `period` is set, the trigger shows the dates instead of a preset label.",
      "People can also type a range above the presets, such as `last 10 days`, `2w`, `Sep 1 - 30`, or `since Oct 3`. While typing, the presets give way to the ranges the text could mean, such as the last 3 days, hours, weeks, months, and years for `3`. Weeks, months, and years are only guessed up to 52, 24, and 3, and with `min` set, nothing that starts before it is suggested. The highlighted one shows on the calendar, arrow keys move the highlight, and Enter or a click applies it. Rolling ranges arrive as a preset id like `last-10-days`, which `TuistWeb.Helpers.DatePicker` reads back from the URL; other typed ranges arrive as `custom`.",
      "Clicking a preset applies it and closes the picker. Days picked on the calendar, and the `custom` preset, wait for the Apply button: put it in the `:actions` slot. It dispatches `phx:date-picker-apply` with the picker's `id`, and shows at full width under the date inputs. There is no Cancel button: clicking outside the panel dismisses the picker without applying.",
      "Applying sends `on_period_change` with the range's `start` and `end` as ISO 8601 strings under `value`, and the `preset` id. Store them and pass them back as `period` and `selected_preset`, with `period` as a tuple of two `DateTime` structs.",
      "Days before `min` or after `max` can't be picked: set `max` to today when there is no data for future dates, as in analytics. `start_of_week` sets the calendar's first column."
    ]

  alias Phoenix.LiveView.JS

  example "Desktop",
    description: "From 768px wide, a field for typing a range and the presets sit beside the calendar.",
    layout: :column do
    ~H"""
    <.date_picker
      id="date-picker-desktop"
      name="analytics-date-range"
      selected_preset="last-7-days"
      max={Date.utc_today()}
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
          label="Apply"
          phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "date-picker-desktop"})}
        />
      </:actions>
    </.date_picker>
    """
  end

  example "Mobile",
    description: "Narrower, the presets scroll as tabs above the calendar, and there is no field for typing.",
    layout: :column,
    device: :mobile do
    ~H"""
    <.date_picker
      id="date-picker-mobile"
      name="analytics-date-range"
      selected_preset="last-7-days"
      max={Date.utc_today()}
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
          label="Apply"
          phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "date-picker-mobile"})}
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
