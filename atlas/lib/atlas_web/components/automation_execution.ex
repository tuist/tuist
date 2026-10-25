defmodule AtlasWeb.AutomationExecution do
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CodeBlock, only: [code_block: 1]
  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Automations.Observability

  attr :run, :map, required: true
  attr :events, :list, required: true
  attr :events_meta, :map, default: nil
  attr :events_error, :boolean, default: false

  def execution_observability(assigns) do
    now = DateTime.utc_now()
    first = assigns.run.trace_started_at || assigns.run.inserted_at
    last = trace_end(assigns.run, now)
    span_us = max(DateTime.diff(last, first, :microsecond), 1)

    assigns =
      assigns
      |> assign(
        :trace_url,
        trace_url(assigns.run.trace_id, Application.get_env(:atlas, :automation_trace_url_template))
      )
      |> assign(:ticks, [{0, "0 ms"}, {50, tick_label(div(span_us, 2))}, {100, tick_label(span_us)}])
      |> assign(:rows, Enum.map(assigns.run.attempts, &trace_row(&1, first, last, span_us)))

    ~H"""
    <.card id="execution-trace" title={gettext("Execution trace")} icon="schema">
      <:actions>
        <.button
          :if={@trace_url}
          href={@trace_url}
          target="_blank"
          rel="noopener noreferrer"
          variant="secondary"
          size="small"
          label={gettext("External trace")}
        />
      </:actions>
      <.card_section>
        <div :if={@run.trace_id} data-part="trace-context">
          <span>{gettext("Trace ID")}</span>
          <code>{@run.trace_id}</code>
          <.button
            id="copy-automation-trace"
            type="button"
            variant="secondary"
            size="small"
            icon_only
            phx-hook="Clipboard"
            data-clipboard-value={@run.trace_id}
            aria-label={gettext("Copy trace ID")}
          >
            <.icon name="copy" />
          </.button>
        </div>
        <p data-part="section-description">
          {gettext(
            "Elapsed intervals include queueing and approval waits. Worker time excludes approval waiting. Missing historical timings are not estimated."
          )}
        </p>
        <.table
          id="execution-waterfall"
          rows={@rows}
          row_key={fn row -> "execution-trace-#{row.attempt.id}" end}
        >
          <:col :let={row} label={gettext("Step")}><.text_cell label={row.attempt.step_id} /></:col>
          <:col :let={row} label={gettext("Timeline (since admission)")}>
            <div data-part="trace-timeline" aria-label={row.label}>
              <div :if={row.segments != []} data-part="trace-axis" aria-hidden="true">
                <span :for={{position, label} <- @ticks} data-position={position}>{label}</span>
              </div>
              <div
                :for={segment <- row.segments}
                data-part="trace-phase-row"
                data-phase={segment.phase}
              >
                <span data-part="trace-phase-label">{phase_label(segment.phase)}</span>
                <div data-part="trace-lane">
                  <span
                    :for={{position, _} <- @ticks}
                    data-part="trace-gridline"
                    style={"left: #{position}%;"}
                  />
                  <div
                    data-part="trace-segment"
                    data-phase={segment.phase}
                    data-at-end={segment.left == 100.0}
                    style={"left: #{segment.left}%; width: #{segment.width}%;"}
                    title={segment.label}
                    role="img"
                    aria-label={segment.label}
                  />
                </div>
              </div>
              <span :if={row.segments == []} data-part="trace-unavailable">
                {gettext("Not recorded")}
              </span>
            </div>
          </:col>
          <:col :let={row} label={gettext("Elapsed")}>
            <.text_cell label={duration_label(row.attempt.duration_ms)} />
          </:col>
          <:col :let={row} label={gettext("Worker time")}>
            <.text_cell label={duration_label(row.attempt.execution_duration_ms)} />
          </:col>
          <:col :let={row} label={gettext("Approval wait")}>
            <.text_cell label={duration_label(row.wait_ms)} />
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="history"
              title={gettext("No step timings yet")}
              subtitle={gettext("Timings appear when a worker claims a step.")}
            />
          </:empty_state>
        </.table>
      </.card_section>
    </.card>
    <.card id="execution-events" title={gettext("Event log")} icon="history">
      <.card_section data-part="records-section">
        <p data-part="section-description">
          {gettext("Newest events first. Payloads and credentials are never copied into this log.")}
        </p>
        <.alert
          :if={@events_error}
          status="warning"
          type="secondary"
          size="small"
          title={gettext("The event log could not be loaded. It will retry on refresh.")}
        />
        <.table
          :if={!@events_error}
          id="execution-event-log"
          rows={@events}
          row_expandable={fn event -> map_size(event.metadata) > 0 end}
        >
          <:col :let={event} label={gettext("Time (UTC)")}>
            <.text_cell label={Calendar.strftime(event.inserted_at, "%b %d, %H:%M:%S") <> "." <> String.pad_leading(to_string(div(elem(event.inserted_at.microsecond, 0), 1000)), 3, "0")} />
          </:col>
          <:col :let={event} label={gettext("Level")}>
            <.badge_cell
              label={event.level}
              color={if event.level == "warning", do: "warning", else: "neutral"}
            />
          </:col>
          <:col :let={event} label={gettext("Step")}>
            <.text_cell label={event.step_id || "—"} />
          </:col>
          <:col :let={event} label={gettext("Event")}>
            <.text_and_description_cell label={event.message} description={event.event} />
          </:col>
          <:expanded_content :let={event}>
            <div data-part="attempt-content">
              <.code_block source={Jason.encode!(event.metadata, pretty: true)} />
            </div>
          </:expanded_content>
          <:empty_state>
            <.table_empty_state
              icon="history"
              title={gettext("No recorded events")}
              subtitle={
                gettext(
                  "New events appear as this execution progresses. Older executions may not have an event log."
                )
              }
            />
          </:empty_state>
        </.table>
        <div :if={@events_meta && @events_meta.total_pages > 1} data-part="pagination">
          <.button
            :if={@events_meta.has_previous_page?}
            variant="secondary"
            size="small"
            label={gettext("Newer events")}
            patch={~p"/automation/executions/#{@run.id}?events_page=#{@events_meta.current_page - 1}"}
          />
          <span>
            {gettext("Page %{page} of %{total}",
              page: @events_meta.current_page,
              total: @events_meta.total_pages
            )}
          </span>
          <.button
            :if={@events_meta.has_next_page?}
            variant="secondary"
            size="small"
            label={gettext("Older events")}
            patch={~p"/automation/executions/#{@run.id}?events_page=#{@events_meta.current_page + 1}"}
          />
        </div>
      </.card_section>
    </.card>
    """
  end

  def duration_label(nil), do: "—"
  def duration_label(ms) when ms < 1000, do: "#{ms} ms"
  def duration_label(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 2)} s"
  def duration_label(ms) when ms < 3_600_000, do: "#{Float.round(ms / 60_000, 2)} min"
  def duration_label(ms), do: "#{Float.round(ms / 3_600_000, 2)} h"

  def trace_url(id, template) when is_binary(id) and is_binary(template) do
    url = String.replace(template, "{trace_id}", id)
    uri = URI.parse(url)

    if Regex.match?(~r/\A[0-9a-f]{32}\z/, id) && String.contains?(template, "{trace_id}") &&
         uri.scheme in ["http", "https"] && is_binary(uri.host) && uri.host != "" && is_nil(uri.userinfo), do: url
  end

  def trace_url(_, _), do: nil

  defp trace_end(run, now) do
    last = run.trace_completed_at || run.completed_at || now

    Enum.reduce(run.attempts, last, fn attempt, last ->
      ended = attempt.completed_at || attempt.wait_started_at || attempt.started_at
      if ended && DateTime.after?(ended, last), do: ended, else: last
    end)
  end

  defp phase_label("execution"), do: gettext("Processing")
  defp phase_label("waiting"), do: gettext("Approval wait")
  defp phase_label("unknown"), do: gettext("Unobserved interval")

  defp tick_label(us) when us > 0 and us < 1000, do: "#{us} µs"
  defp tick_label(us), do: duration_label(div(us, 1000))

  defp trace_row(attempt, first, last, span_us) do
    finish = attempt.completed_at || if(attempt.status in ["running", "waiting_approval"], do: last)
    unknown = attempt.diagnostic != nil || attempt.status == "interrupted"
    phase = if unknown, do: "unknown", else: "execution"
    processing = segment(attempt.started_at, attempt.wait_started_at || finish, first, span_us, phase)
    waiting = segment(attempt.wait_started_at, finish, first, span_us, "waiting")

    wait_ms =
      attempt.wait_duration_ms ||
        if(attempt.wait_started_at && finish, do: Observability.elapsed(attempt.wait_started_at, finish))

    %{
      attempt: attempt,
      wait_ms: wait_ms,
      segments: Enum.reject([processing, waiting], &is_nil/1),
      label: "#{attempt.step_id}: #{attempt.status}; #{duration_label(attempt.duration_ms)}"
    }
  end

  defp segment(nil, _, _, _, _), do: nil
  defp segment(_, nil, _, _, _), do: nil

  defp segment(started, ended, first, span_us, phase) do
    offset = min(max(DateTime.diff(started, first, :microsecond), 0), span_us)
    finish = min(max(DateTime.diff(ended, first, :microsecond), offset), span_us)
    duration = max(DateTime.diff(ended, started, :microsecond), 0)

    label =
      gettext("%{phase}: %{duration}, starting %{offset} after admission",
        phase: phase_label(phase),
        duration: tick_label(duration),
        offset: tick_label(offset)
      )

    %{
      left: Float.round(offset / span_us * 100, 4),
      width: Float.round((finish - offset) / span_us * 100, 4),
      phase: phase,
      label: label
    }
  end
end
