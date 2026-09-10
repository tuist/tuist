defmodule TuistWeb.Components.BuildTimeline do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Components.Skeleton

  attr :timeline, :map, required: true
  attr :version, :integer, required: true
  attr :duration, :integer, required: true
  attr :source, :string, required: true

  def recorded_build_timeline(assigns) do
    ~H"""
    <.async_result :let={timeline} assign={@timeline}>
      <:loading>
        <.card title={dgettext("dashboard_builds", "Build Timeline")} icon="timeline_event">
          <.card_section data-part="timeline-skeleton" aria-busy="true">
            <.skeleton_chart height="652px" />
          </.card_section>
        </.card>
      </:loading>
      <:failed>
        <.card title={dgettext("dashboard_builds", "Build Timeline")} icon="timeline_event">
          <.error_card_section data-part="timeline-error" />
        </.card>
      </:failed>
      <p
        :if={@source == "bazel" and timeline.coverage != "trace_profile"}
        data-part="timeline-coverage"
      >
        {dgettext(
          "dashboard_builds",
          "This build has no trace profile. Only its recorded summary is available. Run tuist bazel setup to enable timeline collection for new builds."
        )}
      </p>
      <p
        :if={@source == "gradle" and timeline.time_origin == "first_recorded_timestamp"}
        data-part="timeline-coverage"
      >
        {dgettext(
          "dashboard_builds",
          "This report has no build start timestamp. Timings are relative to the earliest recorded operation or machine sample."
        )}
      </p>
      <.build_timeline duration={@duration} version={@version} source={@source} />
    </.async_result>
    """
  end

  attr :url, :string, default: nil
  attr :duration, :integer, required: true
  attr :version, :integer, required: true
  attr :source, :string, default: "xcode"

  def build_timeline(assigns) do
    assigns = assign(assigns, :groups, timeline_groups(assigns.source))

    ~H"""
    <div
      id="build-timeline"
      class="tuist-build-timeline"
      data-source={@source}
      phx-hook="BuildTimeline"
      phx-update="ignore"
      data-metric-cores={dgettext("dashboard_builds", "cores")}
      data-metric-in={dgettext("dashboard_builds", "In")}
      data-metric-out={dgettext("dashboard_builds", "Out")}
      data-metric-read={dgettext("dashboard_builds", "Read")}
      data-metric-write={dgettext("dashboard_builds", "Write")}
      data-outcome-labels={
        JSON.encode!(%{
          "local_hit" => dgettext("dashboard_builds", "Local cache hit"),
          "remote_hit" => dgettext("dashboard_builds", "Remote cache hit"),
          "cache_hit" => dgettext("dashboard_builds", "Cache hit"),
          "up_to_date" => dgettext("dashboard_builds", "Up-to-date"),
          "skipped" => dgettext("dashboard_builds", "Skipped"),
          "no_source" => dgettext("dashboard_builds", "No source"),
          "unknown" => dgettext("dashboard_builds", "Unknown")
        })
      }
      data-version={@version}
      data-url={@url}
      data-duration={@duration}
      data-log-loading={dgettext("dashboard_builds", "Loading log…")}
      data-log-empty={dgettext("dashboard_builds", "No log recorded for this step.")}
      data-log-error={
        dgettext("dashboard_builds", "Unable to load the log. Select the step again to retry.")
      }
      data-steps-label={dgettext("dashboard_builds", "steps")}
    >
      <.card title={dgettext("dashboard_builds", "Build Timeline")} icon="timeline_event">
        <:actions>
          <span data-part="summary" hidden>
            <span><span data-stat="duration"></span> {dgettext("dashboard_builds", "elapsed")}</span>
            <span data-part="step-count" hidden><span data-stat="tasks"></span> {dgettext(
              "dashboard_builds",
              "steps"
            )}</span>
            <span data-part="target-count" hidden><span data-stat="targets"></span> {dgettext(
              "dashboard_builds",
              "targets"
            )}</span>
          </span>
        </:actions>
        <.error_card_section data-part="payload-error" hidden />
        <.card_section data-part="timeline-content">
          <div data-part="machine-metrics" hidden>
            <div
              :for={
                {key, label, unit} <- [
                  {"cpu", "CPU", "%"},
                  {"memory", dgettext("dashboard_builds", "Memory"), "GB"},
                  {"network", dgettext("dashboard_builds", "Network"), "MiB/s"},
                  {"disk", dgettext("dashboard_builds", "Disk I/O"), "MiB/s"}
                ]
              }
              data-part="metric-track"
              data-metric={key}
            >
              <div data-part="metric-heading">
                <span>{label}</span>
                <span :if={key in ["network", "disk"]} data-part="metric-series">
                  <span data-series="primary">{if key == "network",
                    do: dgettext("dashboard_builds", "In"),
                    else: dgettext("dashboard_builds", "Read")}</span>
                  <span data-series="secondary">{if key == "network",
                    do: dgettext("dashboard_builds", "Out"),
                    else: dgettext("dashboard_builds", "Write")}</span>
                </span>
                <output data-metric-value={key}>{unit}</output>
              </div>
              <div data-part="metric-plot" tabindex="0">
                <canvas data-metric-ruler={key} aria-hidden="true"></canvas>
                <canvas data-metric-canvas={key} role="img" aria-label={label}></canvas>
                <div data-part="metric-cursor" aria-hidden="true" hidden>
                  <div data-part="cursor-line"></div>
                  <span data-part="cursor-time"></span>
                </div>
                <div data-part="metric-selection" hidden>
                  <span data-part="focus-duration"></span>
                </div>
              </div>
            </div>
          </div>
          <div data-part="payload-loading" aria-busy="true">
            <.skeleton_chart height="652px" />
          </div>
          <div data-part="empty" hidden>
            <.table_empty_state
              icon="timeline_event"
              title={dgettext("dashboard_builds", "No timeline available")}
              subtitle={
                dgettext(
                  "dashboard_builds",
                  "This build has no recorded step timings. Recorded steps are retained for 90 days."
                )
              }
            />
          </div>
          <div data-part="workspace" hidden>
            <div data-part="timeline-chart">
              <div data-part="focus-region" tabindex="-1">
                <div data-part="build-controls">
                  <div data-part="toolbar">
                    <.text_input
                      type="search"
                      id="timeline-search"
                      name="timeline_search"
                      data-control="search"
                      aria-label={
                        if @source == "xcode",
                          do: dgettext("dashboard_builds", "Search steps or targets"),
                          else: dgettext("dashboard_builds", "Search steps, targets, or categories")
                      }
                      placeholder={
                        if @source == "xcode",
                          do: dgettext("dashboard_builds", "Search steps or targets…"),
                          else: dgettext("dashboard_builds", "Search steps, targets, or categories…")
                      }
                      show_suffix={false}
                    />
                  </div>
                  <div data-part="legend">
                    <%= for {kind, label} <- @groups do %>
                      <span :if={@source == "xcode"} data-kind={kind}>{label}</span>
                      <button
                        :if={@source != "xcode"}
                        type="button"
                        data-kind={kind}
                        aria-pressed="false"
                      >{label}</button>
                    <% end %>
                    <output data-part="range"></output>
                  </div>
                </div>
                <canvas data-part="step-ruler" aria-hidden="true"></canvas>
                <div data-part="scrollport">
                  <div data-part="tracks">
                    <canvas
                      data-part="chart"
                      tabindex="0"
                      role="group"
                      aria-label={
                        dgettext(
                          "dashboard_builds",
                          "Build steps. Drag across a time range to focus. Press Escape to cancel a drag. Use the left and right arrow keys to inspect steps. Use plus and minus to zoom, and Home to reset."
                        )
                      }
                    ></canvas>
                  </div>
                </div>
                <div data-part="time-cursor" aria-hidden="true" hidden>
                  <div data-part="cursor-line"></div>
                  <span data-part="cursor-time"></span>
                </div>
                <div data-part="focus-selection" hidden>
                  <span data-part="focus-duration"></span>
                </div>
              </div>
            </div>
            <div
              data-part="inspector-divider"
              role="separator"
              aria-orientation="vertical"
              aria-label={dgettext("dashboard_builds", "Resize step details")}
              aria-controls="timeline-inspector"
              tabindex="0"
              hidden
            >
            </div>
            <aside id="timeline-inspector" data-part="inspector" aria-live="polite" hidden>
              <div data-part="selection" hidden>
                <strong data-detail="title"></strong>
                <dl>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Project")}</dt><dd data-detail="project"></dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Target")}</dt><dd data-detail="target"></dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Type")}</dt>
                    <dd><.badge label="" style="light-fill" data-part="category-badge" /></dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Started after")}</dt><dd data-detail="start">
                    </dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Duration")}</dt>
                    <dd data-part="duration-value">
                      <.history />
                      <span data-detail="duration"></span>
                    </dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Outcome")}</dt>
                    <dd>
                      <.badge label="" style="light-fill" data-part="outcome-other" hidden />
                      <.status_badge
                        status="success"
                        label={dgettext("dashboard_builds", "Succeeded")}
                        data-part="outcome-success"
                        hidden
                      />
                      <.status_badge
                        status="error"
                        label={dgettext("dashboard_builds", "Failed")}
                        data-part="outcome-failure"
                        hidden
                      />
                    </dd>
                  </div>
                </dl>
                <section data-part="step-log">
                  <h4>{dgettext("dashboard_builds", "Log")}</h4>
                  <p data-part="log-status" role="status"></p>
                  <pre data-part="log-content" tabindex="0" hidden></pre>
                  <p data-part="log-truncated" hidden>
                    {dgettext("dashboard_builds", "This log was truncated.")}
                  </p>
                </section>
              </div>
            </aside>
          </div>
          <div data-part="tooltip" role="tooltip" hidden><strong></strong><span></span></div>
          <p data-part="no-recorded-steps" hidden>
            {dgettext("dashboard_builds", "No steps were recorded for this build.")}
          </p>
          <p data-part="no-matches" hidden>
            {dgettext("dashboard_builds", "No steps in this time range match your filters.")}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp timeline_groups(source) do
    groups = [
      {"compile", dgettext("dashboard_builds", "Compilation")},
      {"link", dgettext("dashboard_builds", "Linking")},
      {"script", dgettext("dashboard_builds", "Scripts")}
    ]

    specific =
      case source do
        "bazel" ->
          [
            {"resource", dgettext("dashboard_builds", "File preparation")},
            {"fetch", dgettext("dashboard_builds", "Fetching")},
            {"setup", dgettext("dashboard_builds", "Analysis/setup")}
          ]

        "gradle" ->
          [
            {"resource", dgettext("dashboard_builds", "Resources")},
            {"test", dgettext("dashboard_builds", "Testing")},
            {"package", dgettext("dashboard_builds", "Packaging")},
            {"setup", dgettext("dashboard_builds", "Configuration")},
            {"transform", dgettext("dashboard_builds", "Artifact transforms")}
          ]

        _ ->
          [{"resource", dgettext("dashboard_builds", "Resources")}]
      end

    groups ++
      specific ++
      [
        {"other", dgettext("dashboard_builds", "Other")},
        {"failure", dgettext("dashboard_builds", "Failed")}
      ]
  end
end
