defmodule Noora.DatePicker do
  @moduledoc """
  A date range picker component with preset options and custom selection.

  Built on top of Zag.js date picker machine, this component supports:
  - Predefined range presets (Last 7 days, Last 30 days, etc.) with DateTime precision
  - Custom date range selection via calendar
  - A single-month calendar, with presets in a sidebar on desktop and in tabs on mobile
  - Dismissal by clicking anywhere outside the panel
  - Light/dark mode theming

  ## Example

  ```elixir
  <.date_picker
    id="date-range"
    name="date_range"
    on_period_change="date_range_changed"
    selected_preset={@selected_preset}
    period={@date_range_period}
    presets={[
      %{id: "1h", label: "Last 1 hour", period: {1, :hour}},
      %{id: "24h", label: "Last 24 hours", period: {24, :hour}},
      %{id: "7d", label: "Last 7 days", period: {7, :day}},
      %{id: "30d", label: "Last 30 days", period: {30, :day}},
      %{id: "custom", label: "Custom"}
    ]}
  >
    <:actions>
      <.button
        label="Apply"
        phx-click={JS.dispatch("phx:date-picker-apply", detail: %{id: "date-range"})}
      />
    </:actions>
  </.date_picker>
  ```

  ## Handling period changes

  ```elixir
  def handle_event("date_range_changed", %{"value" => %{"start" => start, "end" => end}, "preset" => preset}, socket) do
    # start and end are ISO8601 DateTime strings
    {:noreply, assign(socket, date_range_period: {start, end})}
  end
  ```
  """
  use Phoenix.Component

  import Noora.Button
  import Noora.ContentDivider
  import Noora.Icon
  import Noora.TextInput

  attr :id, :string, required: true, doc: "Unique identifier for the date picker component"

  attr :label, :string, default: "Select date range", doc: "Label displayed on the trigger button"

  attr :name, :string, default: nil, doc: "The name attribute for the hidden input field"

  attr :period, :any,
    default: nil,
    doc: "The currently selected range as a tuple {start_datetime, end_datetime}. Both values must be DateTime structs."

  attr :presets, :list,
    required: true,
    doc:
      "List of preset options. Each preset is a map with :id, :label, and optional :period keys. Period is a tuple of {amount, unit} where unit is :hour, :day, :week, :month, or :year"

  attr :selected_preset, :string, default: nil, doc: "The ID of the currently selected preset"

  attr :min, :any,
    default: nil,
    doc: "Minimum selectable date (Date, DateTime, or ISO8601 string)"

  attr :max, :any,
    default: nil,
    doc: "Maximum selectable date (Date, DateTime, or ISO8601 string)"

  attr :start_of_week, :integer,
    default: 0,
    doc: "The day the week starts on (0 = Sunday, 1 = Monday, etc.)"

  attr :disabled, :boolean, default: false, doc: "Whether the date picker is disabled"

  attr :typed_ranges, :boolean,
    default: true,
    doc:
      ~s|Whether a range can be typed above the desktop presets, such as "last 10 days". A typed range arrives as a preset id that no preset has, such as "last-10-days", so turn this off where the page only reads its own presets and custom dates.|

  attr :on_period_change, :string,
    default: nil,
    doc: "Event handler name for when the selected date range changes"

  attr :on_cancel, :string,
    default: nil,
    doc: "Event handler name for when the cancel button is clicked"

  attr :open, :boolean,
    default: false,
    doc: "Whether the date picker should be open by default (useful for storybook)"

  attr :rest, :global, doc: "Additional HTML attributes"

  slot :actions,
    required: false,
    doc:
      ~s|The footer's Apply button, shown at full width under the date inputs. Presets apply on click; the button applies days picked on the calendar. Trigger the date picker's apply action with JS.dispatch("phx:date-picker-apply", detail: %{id: id}). Clicking outside the panel dismisses the picker without applying.|

  def date_picker(assigns) do
    presets = assigns.presets
    {period_start, period_end} = extract_period(assigns[:period])

    assigns =
      assigns
      |> assign(:period_start, period_start)
      |> assign(:period_end, period_end)
      |> assign_new(:presets_json, fn ->
        presets
        |> Enum.map(fn preset ->
          %{
            id: preset.id,
            label: preset.label,
            period: encode_preset_period(Map.get(preset, :period))
          }
        end)
        |> Jason.encode!()
      end)
      |> assign_new(:trigger_label, fn ->
        selected_preset = assigns[:selected_preset]

        cond do
          # For custom preset with period values, show the date range
          selected_preset == "custom" && period_start && period_end ->
            format_date_range(period_start, period_end)

          # For other presets, show the preset label
          selected_preset ->
            preset = Enum.find(presets, &(&1.id == selected_preset))

            cond do
              preset -> preset.label
              label = relative_preset_label(selected_preset) -> label
              true -> assigns[:label] || "Select date range"
            end

          # Default label
          true ->
            assigns[:label] || "Select date range"
        end
      end)

    ~H"""
    <div
      id={@id}
      class="noora-date-picker"
      phx-hook="NooraDatePicker"
      data-name={@name}
      data-start-of-week={@start_of_week}
      data-min={encode_date(@min)}
      data-max={encode_date(@max)}
      data-presets={@presets_json}
      data-selected-preset={@selected_preset}
      data-period-start={encode_datetime(@period_start)}
      data-period-end={encode_datetime(@period_end)}
      data-on-period-change={@on_period_change}
      data-on-cancel={@on_cancel}
      data-disabled={@disabled}
      {@rest}
    >
      <div data-part="control">
        <.button
          data-part="trigger"
          type="button"
          variant="secondary"
          label={@trigger_label}
          disabled={@disabled}
        >
          <:icon_left><.calendar /></:icon_left>
        </.button>
      </div>

      <div data-part="positioner">
        <div data-part="content">
          <!-- Desktop: Sidebar presets -->
          <div data-part="presets" data-device="desktop">
            <.text_input
              :if={@typed_ranges}
              id={"#{@id}-range-input"}
              name={"#{@id}-range-input"}
              placeholder="Type a range"
              autocomplete="off"
              aria-label="Type a date range"
              role="combobox"
              aria-autocomplete="list"
              aria-expanded="false"
              aria-controls={"#{@id}-suggestions"}
              data-part="range-input"
              disabled={@disabled}
            />
            <%!-- Filled by the hook while typing, in place of the presets. --%>
            <div
              :if={@typed_ranges}
              id={"#{@id}-suggestions"}
              data-part="suggestions"
              role="listbox"
              aria-label="Suggested ranges"
              phx-update="ignore"
            >
            </div>
            <button
              :for={preset <- @presets}
              type="button"
              data-part="preset-item"
              data-preset-id={preset.id}
              data-selected={if @selected_preset == preset.id, do: "true"}
              disabled={@disabled}
            >
              {preset.label}
            </button>
          </div>

          <!-- Mobile: Tab presets -->
          <div data-part="presets" data-device="mobile">
            <button
              :for={preset <- @presets}
              type="button"
              data-part="preset-item"
              data-preset-id={preset.id}
              data-selected={if @selected_preset == preset.id, do: "true"}
              disabled={@disabled}
            >
              {preset.label}
            </button>
          </div>

          <!-- Calendar area -->
          <div data-part="calendar">
            <div data-part="month">
              <div data-part="view-control">
                <.ghost_button
                  type="button"
                  variant="secondary"
                  size="small"
                  data-part="prev-trigger"
                  aria-label="Previous month"
                  disabled={@disabled}
                >
                  <.chevron_left />
                </.ghost_button>
                <span data-part="view-trigger"></span>
                <.ghost_button
                  type="button"
                  variant="secondary"
                  size="small"
                  data-part="next-trigger"
                  aria-label="Next month"
                  disabled={@disabled}
                >
                  <.chevron_right />
                </.ghost_button>
              </div>
              <table data-part="table">
                <thead data-part="table-head">
                  <tr data-part="table-row">
                    <th :for={_day <- 1..7} data-part="table-header"></th>
                  </tr>
                </thead>
                <tbody data-part="table-body">
                  <tr :for={_week <- 1..6} data-part="table-row">
                    <td :for={_day <- 1..7} data-part="day-table-cell">
                      <button type="button" data-part="table-cell-trigger" disabled={@disabled}></button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <.content_divider />
            <!-- Footer -->
            <div data-part="footer">
              <div data-part="range-display">
                <.date_input_group type="start" disabled={@disabled} />
                <div data-part="range-arrow">
                  <.arrow_narrow_right />
                </div>
                <.date_input_group type="end" disabled={@disabled} />
              </div>
              <div :if={@actions != []} data-part="actions">
                {render_slot(@actions)}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp extract_period(nil), do: {nil, nil}
  defp extract_period({start_dt, end_dt}), do: {start_dt, end_dt}

  # encode_date is used for min/max which can be Date, DateTime, or string
  defp encode_date(nil), do: nil
  defp encode_date(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_date(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_date(str) when is_binary(str), do: str

  # encode_datetime is used for period start/end which must be DateTime
  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp encode_preset_period(nil), do: nil
  defp encode_preset_period({amount, unit}), do: %{amount: amount, unit: to_string(unit)}

  # A typed rolling range comes back as an id that no preset has, such as
  # "last-10-days". Typing is English only, so is its label.
  defp relative_preset_label(id) do
    case Regex.run(~r/^last-(\d+)-(hour|day|week|month|year)s?$/, id) do
      [_, "1", unit] -> "Last #{unit}"
      [_, amount, unit] -> "Last #{amount} #{unit}s"
      nil -> nil
    end
  end

  # The range in words, naming the month and year only where they change:
  # "Sep 1 - 30, 2026", "Jan 31 - Mar 2, 2028", "Dec 28, 2025 - Jan 3, 2026",
  # or "Nov 25, 2026" for a single day. The hook labels an applied range the
  # same way (formatRange in js/DatePicker/rangeParser.js).
  defp format_date_range(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    if DateTime.to_date(start_dt) == DateTime.to_date(end_dt) do
      Calendar.strftime(start_dt, "%b %-d, %Y")
    else
      format_date_span(start_dt, end_dt)
    end
  end

  defp format_date_span(start_dt, end_dt) do
    {start_format, end_format} =
      cond do
        start_dt.year != end_dt.year -> {"%b %-d, %Y", "%b %-d, %Y"}
        start_dt.month != end_dt.month -> {"%b %-d", "%b %-d, %Y"}
        true -> {"%b %-d", "%-d, %Y"}
      end

    "#{Calendar.strftime(start_dt, start_format)} - #{Calendar.strftime(end_dt, end_format)}"
  end

  # Private component for date input fields
  attr :type, :string, required: true
  attr :disabled, :boolean, default: false

  defp date_input_group(assigns) do
    ~H"""
    <div data-part="date-display" data-type={@type} data-format="dmy">
      <input
        type="text"
        data-part="date-input"
        data-field="day"
        placeholder="DD"
        maxlength="2"
        disabled={@disabled}
      />
      <span data-part="date-separator" aria-hidden="true">/</span>
      <input
        type="text"
        data-part="date-input"
        data-field="month"
        placeholder="MM"
        maxlength="2"
        disabled={@disabled}
      />
      <span data-part="date-separator" aria-hidden="true">/</span>
      <input
        type="text"
        data-part="date-input"
        data-field="year"
        placeholder="YYYY"
        maxlength="4"
        disabled={@disabled}
      />
    </div>
    """
  end
end
