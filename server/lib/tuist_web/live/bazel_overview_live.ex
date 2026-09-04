defmodule TuistWeb.BazelOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Time

  alias Tuist.ReapiCache
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.Helpers.DatePicker

  def assign_handle_params(socket, params, uri_path) do
    uri = URI.new!("?" <> URI.encode_query(params))
    project = socket.assigns.selected_project

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    socket
    |> assign(
      uri: uri,
      uri_path: uri_path,
      analytics_preset: analytics_preset,
      analytics_period: analytics_period
    )
    |> assign_async(:reapi_cache_summary, fn ->
      {:ok, %{reapi_cache_summary: ReapiCache.summary(project.id, analytics_period)}}
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="bazel-overview">
      <.card title={dgettext("dashboard_projects", "Bazel remote cache")} icon="server">
        <:actions>
          <.date_picker
            id="analytics-date-range-picker"
            name="analytics-date-range"
            presets={[
              %{
                id: "last-24-hours",
                label: dgettext("dashboard_projects", "Last 24 hours"),
                period: {24, :hour}
              },
              %{
                id: "last-7-days",
                label: dgettext("dashboard_projects", "Last 7 days"),
                period: {7, :day}
              },
              %{
                id: "last-30-days",
                label: dgettext("dashboard_projects", "Last 30 days"),
                period: {30, :day}
              },
              %{
                id: "last-12-months",
                label: dgettext("dashboard_projects", "Last 12 months"),
                period: {12, :month}
              },
              %{id: "custom", label: dgettext("dashboard_projects", "Custom")}
            ]}
            selected_preset={@analytics_preset}
            period={@analytics_period}
            on_period_change="analytics_period_changed"
            max={Date.utc_today()}
          >
            <:actions>
              <.button
                label={dgettext("dashboard_projects", "Cancel")}
                variant="secondary"
                phx-click={
                  JS.dispatch("phx:date-picker-cancel", detail: %{id: "analytics-date-range-picker"})
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply", detail: %{id: "analytics-date-range-picker"})
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <.card_section data-part="bazel-remote-cache">
          <span data-part="description">
            {dgettext(
              "dashboard_projects",
              "These are remote-cache observations from Kura. Open Invocations for completed Bazel commands and their attributable cache totals."
            )}
          </span>
          <div data-part="widgets">
            <.widget
              loading={!@reapi_cache_summary.ok?}
              title={dgettext("dashboard_projects", "Action cache hit rate")}
              description={
                dgettext(
                  "dashboard_projects",
                  "The share of action-cache lookups that Kura served from the remote cache."
                )
              }
              value={
                if @reapi_cache_summary.ok? and @reapi_cache_summary.result.hit_rate,
                  do: "#{@reapi_cache_summary.result.hit_rate}%"
              }
              id="bazel-action-cache-hit-rate"
              empty={@reapi_cache_summary.ok? && is_nil(@reapi_cache_summary.result.hit_rate)}
            />
            <.widget
              loading={!@reapi_cache_summary.ok?}
              title={dgettext("dashboard_projects", "Action cache lookups")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Remote action-cache hits and misses observed by Kura."
                )
              }
              value={
                if @reapi_cache_summary.ok?,
                  do: "#{@reapi_cache_summary.result.hits + @reapi_cache_summary.result.misses}"
              }
              id="bazel-action-cache-lookups"
              empty={
                @reapi_cache_summary.ok? &&
                  @reapi_cache_summary.result.hits + @reapi_cache_summary.result.misses == 0
              }
            />
            <.widget
              loading={!@reapi_cache_summary.ok?}
              title={dgettext("dashboard_projects", "Downloaded from remote cache")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Bytes Kura served from the remote cache."
                )
              }
              value={
                if @reapi_cache_summary.ok?,
                  do: ByteFormatter.format_bytes(@reapi_cache_summary.result.download_bytes)
              }
              id="bazel-cache-downloads"
              empty={@reapi_cache_summary.ok? && @reapi_cache_summary.result.download_bytes == 0}
            />
            <.widget
              loading={!@reapi_cache_summary.ok?}
              title={dgettext("dashboard_projects", "Uploaded to remote cache")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Bytes Kura accepted for the remote cache."
                )
              }
              value={
                if @reapi_cache_summary.ok?,
                  do: ByteFormatter.format_bytes(@reapi_cache_summary.result.upload_bytes)
              }
              id="bazel-cache-uploads"
              empty={@reapi_cache_summary.ok? && @reapi_cache_summary.result.upload_bytes == 0}
            />
          </div>
          <p
            :if={@reapi_cache_summary.ok? && @reapi_cache_summary.result.last_observed_at}
            data-part="bazel-latest-observation"
          >
            {dgettext("dashboard_projects", "Latest observation:")}
            <.time
              time={@reapi_cache_summary.result.last_observed_at}
              show_time
            />
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end
end
