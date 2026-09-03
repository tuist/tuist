defmodule TuistWeb.BazelInvocationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Bazel
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Invocations")} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("overview"))
      |> assign_async(:invocation_summary, fn -> {:ok, %{invocation_summary: Bazel.summary(project.id)}} end)

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    page = parse_page(params["page"])
    status = params["status"]

    filters = maybe_append_status([%{field: :project_id, op: :==, value: project.id}], status)

    {invocations, meta} =
      Bazel.list_invocations(project.id, %{
        filters: filters,
        order_by: [:finished_at],
        order_directions: [:desc],
        page: page,
        page_size: @page_size
      })

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:invocations, invocations)
     |> assign(:current_page, meta.current_page)
     |> assign(:total_pages, meta.total_pages)
     |> assign(:status, status)}
  end

  def render(assigns) do
    ~H"""
    <div id="bazel-invocations" class="bazel-invocations">
      <.card title={dgettext("dashboard_projects", "Invocations")} icon="versions">
        <.card_section data-part="bazel-invocation-summary">
          <span data-part="description">
            {dgettext(
              "dashboard_projects",
              "Completed Bazel commands reported through the Build Event Protocol. Cache totals include only remote-cache requests that Bazel attributed to the same invocation."
            )}
          </span>
          <div data-part="widgets">
            <.widget
              id="bazel-total-invocations"
              loading={!@invocation_summary.ok?}
              title={dgettext("dashboard_projects", "Invocations")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Completed Bazel commands in the retained data window."
                )
              }
              value={if @invocation_summary.ok?, do: @invocation_summary.result.total}
              empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
            />
            <.widget
              id="bazel-success-rate"
              loading={!@invocation_summary.ok?}
              title={dgettext("dashboard_projects", "Invocation success rate")}
              description={
                dgettext(
                  "dashboard_projects",
                  "The share of completed commands with a zero exit code."
                )
              }
              value={if @invocation_summary.ok?, do: success_rate(@invocation_summary.result)}
              empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
            />
            <.widget
              id="bazel-median-duration"
              loading={!@invocation_summary.ok?}
              title={dgettext("dashboard_projects", "Median duration")}
              description={
                dgettext("dashboard_projects", "The median duration of completed Bazel commands.")
              }
              value={
                if @invocation_summary.ok?,
                  do:
                    DateFormatter.format_duration_from_milliseconds(
                      @invocation_summary.result.median_duration_ms
                    )
              }
              empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
            />
            <.widget
              id="bazel-p90-duration"
              loading={!@invocation_summary.ok?}
              title={dgettext("dashboard_projects", "90th percentile duration")}
              description={
                dgettext(
                  "dashboard_projects",
                  "The duration below which 90% of completed commands finished."
                )
              }
              value={
                if @invocation_summary.ok?,
                  do:
                    DateFormatter.format_duration_from_milliseconds(
                      @invocation_summary.result.p90_duration_ms
                    )
              }
              empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
            />
          </div>
        </.card_section>
        <.card_section data-part="bazel-invocations-table">
          <div :if={Enum.any?(@invocations)}>
            <.table id="bazel-invocations-table" rows={@invocations}>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Command")}>
                <.text_cell label={invocation.command} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Status")}>
                <.status_badge_cell
                  label={
                    if invocation.status == "success",
                      do: dgettext("dashboard_projects", "Succeeded"),
                      else: dgettext("dashboard_projects", "Failed")
                  }
                  status={if invocation.status == "success", do: "success", else: "error"}
                />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Duration")}>
                <.text_cell
                  label={DateFormatter.format_duration_from_milliseconds(invocation.duration_ms)}
                  icon="history"
                />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Cache hit rate")}>
                <.text_cell label={cache_hit_rate(invocation.cache)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Remote cache transfer")}>
                <.text_cell label={"↓ #{ByteFormatter.format_bytes(invocation.cache.download_bytes)}  ↑ #{ByteFormatter.format_bytes(invocation.cache.upload_bytes)}"} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Finished")}>
                <.text_cell sublabel={DateFormatter.from_now(invocation.finished_at)} />
              </:col>
            </.table>
            <.pagination_group
              :if={@total_pages > 1}
              current_page={@current_page}
              number_of_pages={@total_pages}
              page_patch={fn page -> "?#{Query.put(@uri.query, "page", to_string(page))}" end}
            />
          </div>
          <p :if={Enum.empty?(@invocations)} data-part="empty-bazel-invocations">
            {dgettext(
              "dashboard_projects",
              "No Bazel invocations have been received yet. Run tuist bazel setup, then run a Bazel command."
            )}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp maybe_append_status(filters, status) when status in ["success", "failure"],
    do: filters ++ [%{field: :status, op: :==, value: status}]

  defp maybe_append_status(filters, _status), do: filters

  defp parse_page(value) do
    case Integer.parse(value || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp success_rate(%{total: 0}), do: nil
  defp success_rate(summary), do: "#{Float.round(summary.successful / summary.total * 100, 1)}%"

  defp cache_hit_rate(%{hit_rate: nil}), do: dgettext("dashboard_projects", "No cache lookups")
  defp cache_hit_rate(%{hit_rate: hit_rate}), do: "#{hit_rate}%"
end
