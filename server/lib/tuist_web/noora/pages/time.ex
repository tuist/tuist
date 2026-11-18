defmodule TuistWeb.Noora.Pages.Time do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Time",
    description: "Renders a date, a date and time, or a relative time from a `DateTime`.",
    components: [{Noora.Time, :time}],
    guidelines: [
      "Pass a `DateTime`. The component calls `DateTime.to_iso8601/1` on it, so a `NaiveDateTime` raises.",
      "The value is formatted in the time zone it carries and without a zone label. Convert it before rendering if the reader expects another zone.",
      "Show the date alone by default. Add `show_time` when the exact moment matters, such as for a build start.",
      "Use `relative` for recent activity, such as the last run of a test. The full date appears in a tooltip on hover.",
      "Inside tables, use the table's `time_cell`, which takes the same attributes."
    ]

  example "Date", description: "The default shows the date alone." do
    ~H"""
    <.time time={~U[2026-10-01 09:30:00Z]} />
    """
  end

  example "Date and time", description: "`show_time` adds the time of day with seconds." do
    ~H"""
    <.time time={~U[2026-10-01 09:30:00Z]} show_time />
    """
  end

  example "Relative", description: "`relative` shows the distance from now. Hover it to see the full date." do
    ~H"""
    <.time time={~U[2026-10-01 09:30:00Z]} relative />
    """
  end

  example "Relative with time", description: "With both, the tooltip includes the time of day." do
    ~H"""
    <.time time={~U[2026-10-01 09:30:00Z]} relative show_time />
    """
  end
end
