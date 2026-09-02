defmodule TuistWeb.BazelOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.ReapiCache
  alias Tuist.Utilities.ByteFormatter

  def assign_mount(socket) do
    project = socket.assigns.selected_project

    assign_async(socket, :reapi_cache_summary, fn ->
      {:ok, %{reapi_cache_summary: ReapiCache.summary(project.id)}}
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="bazel-overview">
      <.card title={dgettext("dashboard_projects", "Bazel remote cache")} icon="server">
        <.card_section data-part="bazel-remote-cache">
          <span data-part="description">
            {dgettext(
              "dashboard_projects",
              "These are remote-cache observations from Kura. They do not include build or test results."
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
                  "Bytes Kura served while returning action-cache results."
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
                  "Bytes Kura accepted while storing action-cache results."
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
            {dgettext("dashboard_projects", "Latest observation: %{timestamp}",
              timestamp: format_observed_at(@reapi_cache_summary.result.last_observed_at)
            )}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp format_observed_at(observed_at) do
    Calendar.strftime(observed_at, "%b %-d, %Y %H:%M UTC")
  end
end
