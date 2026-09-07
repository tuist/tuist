defmodule TuistWeb.Components.BuildTimeline do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Components.Skeleton

  attr :timeline, :map, required: true
  attr :duration, :integer, required: true
  attr :version, :integer, required: true

  def build_timeline(assigns) do
    ~H"""
    <.card
      :if={@timeline.events == []}
      title={dgettext("dashboard_builds", "Build Timeline")}
      icon="timeline_event"
    >
      <.card_section>
        <.table_empty_state
          icon="timeline_event"
          title={dgettext("dashboard_builds", "No timeline available")}
          subtitle={
            dgettext(
              "dashboard_builds",
              "This build has no recorded step timings. Timelines are available for newly processed builds and are retained for 90 days."
            )
          }
        />
      </.card_section>
    </.card>
    <div
      :if={@timeline.events != []}
      id="build-timeline"
      class="tuist-build-timeline"
      phx-hook="BuildTimeline"
      phx-update="ignore"
      data-version={@version}
      data-duration={@duration}
      data-log-loading={dgettext("dashboard_builds", "Loading log…")}
      data-log-empty={dgettext("dashboard_builds", "No log recorded for this step.")}
      data-log-error={
        dgettext("dashboard_builds", "Unable to load the log. Select the step again to retry.")
      }
      data-success-label={dgettext("dashboard_builds", "Succeeded")}
      data-build-label={dgettext("dashboard_builds", "Build operations")}
    >
      <.card title={dgettext("dashboard_builds", "Build Timeline")} icon="timeline_event">
        <:actions>
          <span data-part="summary" hidden>
            <span><span data-stat="duration"></span> {dgettext("dashboard_builds", "elapsed")}</span>
            <span><span data-stat="tasks"></span> {dgettext("dashboard_builds", "steps")}</span>
            <span><span data-stat="targets"></span> {dgettext("dashboard_builds", "targets")}</span>
          </span>
        </:actions>
        <.card_section data-part="payload-loading">
          <.skeleton_chart height="532px" />
        </.card_section>
        <.error_card_section data-part="payload-error" hidden />
        <.card_section data-part="timeline-content" hidden>
          <p :if={@timeline.truncated} data-part="notice">
            {dgettext(
              "dashboard_builds",
              "Showing the first 50,000 steps. This timeline is incomplete."
            )}
          </p>
          <div data-part="toolbar">
            <.text_input
              type="search"
              id="timeline-search"
              name="timeline_search"
              data-control="search"
              aria-label={dgettext("dashboard_builds", "Search steps or targets")}
              placeholder={dgettext("dashboard_builds", "Search steps or targets…")}
              show_suffix={false}
            />
          </div>
          <div data-part="legend">
            <span data-kind="compile">{dgettext("dashboard_builds", "Compilation")}</span>
            <span data-kind="link">{dgettext("dashboard_builds", "Linking")}</span>
            <span data-kind="script">{dgettext("dashboard_builds", "Scripts")}</span>
            <span data-kind="resource">{dgettext("dashboard_builds", "Resources")}</span>
            <span data-kind="other">{dgettext("dashboard_builds", "Other")}</span>
            <span data-kind="failure">{dgettext("dashboard_builds", "Failed")}</span>
            <output data-part="range"></output>
          </div>
          <div data-part="workspace">
            <div data-part="timeline-chart">
              <div data-part="focus-region" tabindex="-1">
                <canvas data-part="ruler" aria-hidden="true"></canvas>
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
              <div data-part="tooltip" role="tooltip" hidden><strong></strong><span></span></div>
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
                    <dt>{dgettext("dashboard_builds", "Target")}</dt><dd data-detail="target"></dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Type")}</dt><dd data-detail="category"></dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Started after")}</dt><dd data-detail="start">
                    </dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Duration")}</dt><dd data-detail="duration">
                    </dd>
                  </div>
                  <div>
                    <dt>{dgettext("dashboard_builds", "Outcome")}</dt><dd data-detail="status"></dd>
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
          <p data-part="no-matches" hidden>
            {dgettext("dashboard_builds", "No steps in this time range match your filters.")}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end
end
