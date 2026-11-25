defmodule TuistWeb.RemoteExecutionLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Projects.Project
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.Analytics
  alias Tuist.RemoteExecution.RunAnalytics
  alias Tuist.RemoteExecution.Usage
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Components.ErrorCardSection
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  # Usage widgets read the execution ledger; profile widgets read Bazel profiles.
  @usage_widgets ~w(executions execution-time)
  @profile_widgets ~w(execution queue)
  @stats ~w(avg p50 p90 p99)
  @sort_fields ~w(ran-at duration actions execution execution-p50 execution-p90 status)
  @running_refresh_ms 5_000

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !(Project.bazel_project?(project) or Project.once_project?(project)), do: raise(NotFoundError)
    once? = Project.once_project?(project)
    if connected?(socket), do: Process.send_after(self(), :refresh_running, @running_refresh_ms)

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard", "Remote execution")} · #{account.name}/#{project.name} · Tuist")
     |> assign(:once?, once?)
     |> assign(:available_filters, available_filters())
     |> assign(:sort_fields, @sort_fields)
     |> assign_async(:running, fn ->
       {:ok, %{running: RemoteExecution.running_invocations(project)}}
     end)
     |> assign(OpenGraph.og_image_assigns("overview"))}
  end

  def handle_info(:refresh_running, socket) do
    project = socket.assigns.selected_project
    {:noreply, start_async(socket, :refresh_running, fn -> RemoteExecution.running_invocations(project) end)}
  end

  # A failed refresh keeps the last snapshot; the next one replaces it.
  def handle_async(:refresh_running, result, socket) do
    Process.send_after(self(), :refresh_running, @running_refresh_ms)

    case result do
      {:ok, running} -> {:noreply, assign(socket, :running, AsyncResult.ok(running))}
      {:exit, _reason} -> {:noreply, socket}
    end
  end

  def handle_params(params, _uri, socket) do
    %{preset: preset, period: period} = period_selection(params)
    once? = socket.assigns.once?
    search = String.slice(params["search"] || "", 0, 512)
    sort_by = param(params, "invocations-sort-by", @sort_fields)
    sort_order = param(params, "invocations-sort-order", ~w(desc asc))
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    filters = Filter.Operations.convert_filters_to_flop(active_filters)
    page = Query.positive_integer(params["page"])
    cohort = period
    project = socket.assigns.selected_project
    opts = DatePicker.period_opts(period)

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(Map.drop(params, ~w(account_handle project_handle)))))
      |> assign(:preset, preset)
      |> assign(:period, period)
      |> assign(:trend_label, analytics_trend_label(preset))
      |> assign(:search, search)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign(:active_filters, active_filters)
      |> assign(:selected_widget, param(params, "analytics-selected-widget", widgets(once?)))
      |> assign(:queue_type, param(params, "queue-type", @stats))
      |> assign(:execution_type, param(params, "execution-type", @stats))
      |> assign_async(:activity, fn ->
        {:ok,
         %{
           activity:
             analytics(once?).activity(
               project.id,
               Keyword.merge(opts,
                 page: page,
                 search: search,
                 filters: filters,
                 sort_by: sort_by,
                 sort_order: sort_order
               )
             )
         }}
      end)

    # Search, pagination and widget selection do not change the usage.
    socket =
      if socket.assigns[:usage_period] == period and is_nil(socket.assigns.usage.failed) do
        socket
      else
        socket
        |> assign(:usage_period, period)
        |> assign_async(:usage, fn -> {:ok, %{usage: usage_with_trends(project, period)}} end)
      end

    # Search, pagination and widget selection do not change the analytics cohort.
    socket =
      if socket.assigns[:cohort] == cohort and is_nil(socket.assigns.summary.failed) do
        socket
      else
        assign_async(socket, [:summary, :series], fn ->
          {:ok,
           %{
             summary: summary_with_trends(analytics(once?), project.id, period),
             series: analytics(once?).time_series(project.id, opts)
           }}
        end)
      end

    {:noreply, assign(socket, :cohort, cohort)}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket)
      when widget in @usage_widgets or widget in @profile_widgets do
    {:noreply, replace_query(socket, %{"analytics-selected-widget" => widget}, selected_widget: widget)}
  end

  def handle_event("select_queue_type", %{"type" => type}, socket) when type in @stats do
    {:noreply,
     replace_query(socket, %{"queue-type" => type, "analytics-selected-widget" => "queue"},
       queue_type: type,
       selected_widget: "queue"
     )}
  end

  def handle_event("select_execution_type", %{"type" => type}, socket) when type in @stats do
    {:noreply,
     replace_query(socket, %{"execution-type" => type, "analytics-selected-widget" => "execution"},
       execution_type: type,
       selected_widget: "execution"
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = filter_id |> Filter.Operations.add_filter_to_query(socket) |> Map.delete("page")

    socket
    |> push_patch(to: list_path(socket.assigns, params))
    |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
    |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})
    |> then(&{:noreply, &1})
  end

  def handle_event("update_filter", params, socket) do
    params = params |> Filter.Operations.update_filters_in_query(socket) |> Map.delete("page")

    socket
    |> push_patch(to: list_path(socket.assigns, params))
    |> push_event("close-dropdown", %{id: "all", all: true})
    |> push_event("close-popover", %{id: "all", all: true})
    |> then(&{:noreply, &1})
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: patch_path(socket.assigns, %{"search" => search, "page" => nil}))}
  end

  def handle_event("period_changed", %{"value" => %{"start" => first, "end" => last}, "preset" => preset}, socket) do
    custom? = preset == "custom"

    {:noreply,
     push_patch(socket,
       to:
         patch_path(socket.assigns, %{
           "analytics-date-range" => preset,
           "analytics-start-date" => if(custom?, do: first),
           "analytics-end-date" => if(custom?, do: last),
           "page" => nil
         })
     )}
  end

  def render(assigns) do
    assigns = assign(assigns, :timings, timings_state(assigns.summary, assigns.series))

    ~H"""
    <div id="remote-execution" class="bazel-invocations">
      <div data-part="filters">
        <.date_picker
          id="remote-execution-period"
          name="analytics-date-range"
          presets={Enum.reject(date_picker_presets(), &(&1.id == "last-12-months"))}
          selected_preset={@preset}
          period={@period}
          on_period_change="period_changed"
          max={Date.utc_today()}
        >
          <:actions>
            <.button
              label={dgettext("dashboard_projects", "Cancel")}
              variant="secondary"
              phx-click={
                JS.dispatch("phx:date-picker-cancel", detail: %{id: "remote-execution-period"})
              }
            />
            <.button
              label={dgettext("dashboard_projects", "Apply")}
              phx-click={
                JS.dispatch("phx:date-picker-apply", detail: %{id: "remote-execution-period"})
              }
            />
          </:actions>
        </.date_picker>
      </div>

      <.async_card
        :let={ready?}
        results={[@usage]}
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        chart_frame="small"
        data-part="bazel-invocation-analytics-card"
      >
        <div data-part="widgets">
          <.widget
            id="remote-execution-executions"
            loading={!ready?}
            title={dgettext("dashboard_builds", "Executions")}
            legend_color="primary"
            description={
              dgettext(
                "dashboard_builds",
                "Remote actions that ran in a VM, as the execution node recorded them. Results served from the cache are not executions."
              )
            }
            value={if ready?, do: @usage.result.executions}
            trend_value={if ready?, do: @usage.result.executions_trend}
            trend_label={@trend_label}
            trend_type={:neutral}
            empty={ready? && @usage.result.executions == 0}
            phx_click="select_widget"
            phx_value_widget="executions"
            selected={@selected_widget == "executions"}
          />
          <.widget
            id="remote-execution-execution-time"
            loading={!ready?}
            title={dgettext("dashboard_builds", "Total execution time")}
            legend_color="primary"
            description={
              dgettext(
                "dashboard_builds",
                "Time the executor ran in each action's VM, from its start to its exit, summed over executions. It includes fetching inputs and uploading outputs, but not queueing or preparing the VM. The Usage page bills this time per machine shape."
              )
            }
            value={
              if ready?,
                do: DateFormatter.format_duration_from_milliseconds(@usage.result.execution_ms)
            }
            trend_value={if ready?, do: @usage.result.execution_ms_trend}
            trend_label={@trend_label}
            trend_type={:neutral}
            empty={ready? && @usage.result.executions == 0}
            phx_click="select_widget"
            phx_value_widget="execution-time"
            selected={@selected_widget == "execution-time"}
          />
          <.percentile_dropdown_widget
            id="remote-execution-queue"
            loading={!ready? or @timings == :loading}
            title={phase_title(:queue, @queue_type)}
            description={
              dgettext(
                "dashboard_builds",
                "Time actions waited for a remote worker. Actions without a recorded queue phase are excluded."
              )
            }
            value={if @timings == :ready, do: phase_value(@summary.result, :queue, @queue_type)}
            metrics={if @timings == :ready, do: phase_metrics(@summary.result, :queue)}
            selected_type={@queue_type}
            legend_color={legend_color(@queue_type)}
            event_name="select_queue_type"
            phx_click="select_widget"
            phx_value_widget="queue"
            selected={@selected_widget == "queue"}
            trend_value={if @timings == :ready, do: @summary.result.trends.queue[stat(@queue_type)]}
            trend_label={@trend_label}
            trend_type={:inverse}
            empty={@timings == :failed or (@timings == :ready && is_nil(@summary.result.queue.avg))}
            empty_label={if @timings == :failed, do: dgettext("dashboard_builds", "Couldn't load")}
          />
          <.percentile_dropdown_widget
            id="remote-execution-duration"
            loading={!ready? or @timings == :loading}
            title={phase_title(:execution, @execution_type)}
            description={
              dgettext(
                "dashboard_builds",
                "Time actions ran on a remote worker. This is per-action work, not build wall time or billed VM time."
              )
            }
            value={
              if @timings == :ready, do: phase_value(@summary.result, :execution, @execution_type)
            }
            metrics={if @timings == :ready, do: phase_metrics(@summary.result, :execution)}
            selected_type={@execution_type}
            legend_color={legend_color(@execution_type)}
            event_name="select_execution_type"
            phx_click="select_widget"
            phx_value_widget="execution"
            selected={@selected_widget == "execution"}
            trend_value={
              if @timings == :ready, do: @summary.result.trends.execution[stat(@execution_type)]
            }
            trend_label={@trend_label}
            trend_type={:inverse}
            empty={
              @timings == :failed or (@timings == :ready && is_nil(@summary.result.execution.avg))
            }
            empty_label={if @timings == :failed, do: dgettext("dashboard_builds", "Couldn't load")}
          />
        </div>
        <.card_section
          :if={!ready? or (@timings == :loading && @selected_widget in ~w(execution queue))}
          data-part="analytics-card-chart-section"
          data-chart-frame="standard"
        >
          <.skeleton_chart />
        </.card_section>
        <.card_section
          :if={
            ready? && @selected_widget in ~w(executions execution-time) &&
              @usage.result.executions > 0
          }
          data-part="analytics-card-chart-section"
          data-chart-frame="standard"
        >
          <.chart
            id="remote-execution-usage-chart"
            type="line"
            extra_options={usage_chart_options(@usage.result, @selected_widget)}
            series={usage_chart_series(@usage.result, @selected_widget)}
            y_axis_min={0}
          />
        </.card_section>
        <.empty_card_section
          :if={
            ready? && @selected_widget in ~w(executions execution-time) &&
              @usage.result.executions == 0
          }
          title={dgettext("dashboard_builds", "No remote executions in this period")}
          data-part="analytics-card-chart-section"
          data-chart-frame="standard"
        >
          <:image>
            <img src={~p"/images/empty_line_chart_light.png"} data-theme="light" loading="lazy" />
            <img src={~p"/images/empty_line_chart_dark.png"} data-theme="dark" loading="lazy" />
          </:image>
        </.empty_card_section>
        <.card_section
          :if={
            ready? && @timings == :ready && @selected_widget in ~w(execution queue) &&
              has_data?(@series.result, @selected_widget)
          }
          data-part="analytics-card-chart-section"
          data-chart-frame="standard"
        >
          <.chart
            id="remote-execution-chart"
            type="line"
            extra_options={chart_options(@series.result)}
            series={chart_series(@series.result, @selected_widget)}
            y_axis_min={0}
          />
        </.card_section>
        <.empty_card_section
          :if={
            ready? && @timings == :ready && @selected_widget in ~w(execution queue) &&
              !has_data?(@series.result, @selected_widget)
          }
          title={dgettext("dashboard_builds", "No remote execution timings in this period")}
          data-part="analytics-card-chart-section"
          data-chart-frame="standard"
        >
          <:image>
            <img src={~p"/images/empty_line_chart_light.png"} data-theme="light" loading="lazy" />
            <img src={~p"/images/empty_line_chart_dark.png"} data-theme="dark" loading="lazy" />
          </:image>
        </.empty_card_section>
        <ErrorCardSection.error_card_section
          :if={ready? && @timings == :failed && @selected_widget in ~w(execution queue)}
          data-part="analytics-card-chart-section"
          data-chart-frame="standard"
        />
      </.async_card>

      <.card
        title={
          if @once?,
            do: dgettext("dashboard_builds", "Runs"),
            else: dgettext("dashboard_builds", "Invocations")
        }
        icon="subtask"
        data-part="bazel-invocations-card"
      >
        <.card_section data-part="bazel-invocations-table-section">
          <div data-part="filters">
            <.form for={%{}} id="remote-execution-search-form" phx-change="search" phx-submit="search">
              <.text_input
                id="remote-execution-search"
                name="search"
                type="search"
                value={@search}
                placeholder={dgettext("dashboard_builds", "Search invocations...")}
                show_suffix={false}
                phx-debounce="200"
              />
            </.form>
            <.dropdown
              id="remote-execution-sort-by"
              label={sort_label(@sort_by)}
              secondary_text={dgettext("dashboard_builds", "Sort by:")}
            >
              <.dropdown_item
                :for={column <- @sort_fields}
                value={column}
                label={sort_label(column)}
                patch={sort_path(assigns, column)}
                data-selected={@sort_by == column}
              >
                <:right_icon :if={@sort_by == column}><.check /></:right_icon>
              </.dropdown_item>
            </.dropdown>
            <.filter_dropdown
              id="remote-execution-filter-dropdown"
              label={dgettext("dashboard_projects", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
          </div>
          <div :if={Enum.any?(@active_filters)} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <.async_result :let={activity} assign={@activity}>
            <:loading><.skeleton_chart /></:loading>
            <:failed>
              <ErrorCardSection.error_state />
            </:failed>
            <div
              :if={running_rows(@running, activity.page, assigns) != [] or activity.rows != []}
              data-part="bazel-invocations-table"
            >
              <.table
                id="remote-execution-activity"
                rows={
                  Enum.map(
                    running_rows(@running, activity.page, assigns),
                    &Map.put(&1, :running?, true)
                  ) ++
                    activity.rows
                }
                row_key={
                  &if(&1[:running?], do: "running-" <> &1.invocation_id, else: &1.invocation_id)
                }
                row_navigate={&invocation_path(assigns, &1)}
              >
                <:col
                  :let={row}
                  label={
                    if @once?,
                      do: dgettext("dashboard_builds", "Run"),
                      else: dgettext("dashboard_projects", "Invocation")
                  }
                >
                  <.text_cell label={
                    if row[:running?], do: running_command(row), else: invocation_label(row, @once?)
                  } />
                </:col>
                <:col
                  :let={row}
                  label={dgettext("dashboard_projects", "Status")}
                  patch={sort_path(assigns, "status")}
                  sort_order={sort_order(assigns, "status")}
                >
                  <.status_badge_cell
                    :if={row[:running?]}
                    label={dgettext("dashboard_builds", "Running")}
                    status="in_progress"
                  />
                  <.status_badge_cell
                    :if={!row[:running?]}
                    label={
                      if row.status == "success",
                        do: dgettext("dashboard_projects", "Succeeded"),
                        else: dgettext("dashboard_projects", "Failed")
                    }
                    status={if row.status == "success", do: "success", else: "error"}
                  />
                </:col>
                <:col
                  :let={row}
                  label={dgettext("dashboard_projects", "Duration")}
                  patch={sort_path(assigns, "duration")}
                  sort_order={sort_order(assigns, "duration")}
                >
                  <.text_cell
                    label={
                      DateFormatter.format_duration_from_milliseconds(
                        if(row[:running?],
                          do: max(DateTime.diff(DateTime.utc_now(), row.started_at, :millisecond), 0),
                          else: row.duration_ms
                        ),
                        fractional_seconds: !row[:running?]
                      )
                    }
                    icon="history"
                  />
                </:col>
                <:col
                  :let={row}
                  label={dgettext("dashboard_builds", "Remote actions")}
                  patch={sort_path(assigns, "actions")}
                  sort_order={sort_order(assigns, "actions")}
                >
                  <.text_cell label={
                    if row[:running?], do: running_actions(row), else: format_number(row.actions)
                  } />
                </:col>
                <:col
                  :let={row}
                  label={dgettext("dashboard_builds", "Avg. execution")}
                  patch={sort_path(assigns, "execution")}
                  sort_order={sort_order(assigns, "execution")}
                >
                  <.text_cell label={if row[:running?], do: "–", else: duration(row.execution_ms)} />
                </:col>
                <:col
                  :let={row}
                  :for={stat <- ~w(p50 p90)}
                  label={sort_label("execution-" <> stat)}
                  patch={sort_path(assigns, "execution-" <> stat)}
                  sort_order={sort_order(assigns, "execution-" <> stat)}
                >
                  <.text_cell label={
                    if row[:running?], do: "–", else: duration(row[:"execution_#{stat}_ms"])
                  } />
                </:col>
                <:col
                  :let={row}
                  label={dgettext("dashboard_projects", "Ran at")}
                  patch={sort_path(assigns, "ran-at")}
                  sort_order={sort_order(assigns, "ran-at")}
                >
                  <.text_cell sublabel={
                    DateFormatter.from_now(
                      if(row[:running?], do: row.started_at, else: row.finished_at)
                    )
                  } />
                </:col>
              </.table>
              <.page_pagination
                id="remote-execution-pagination"
                page={activity.page}
                has_next_page={activity.has_next_page?}
                page_patch={&patch_path(assigns, %{"page" => &1})}
              />
            </div>
            <.empty_card_section
              :if={running_rows(@running, activity.page, assigns) == [] and activity.rows == []}
              title={
                if @search == "",
                  do:
                    dgettext(
                      "dashboard_builds",
                      "No invocations with remote execution timings in this period"
                    ),
                  else: dgettext("dashboard_builds", "No invocations match your search")
              }
              get_started_href={
                if @search == "",
                  do:
                    if(@once?,
                      do: "/en/docs/guides/features/runners/struo",
                      else: "/en/docs/guides/features/cache/bazel-cache#remote-execution"
                    )
              }
              data-part="empty-bazel-invocations-card-section"
            >
              <:image>
                <img src={~p"/images/empty_table_light.png"} data-theme="light" loading="lazy" />
                <img src={~p"/images/empty_table_dark.png"} data-theme="dark" loading="lazy" />
              </:image>
            </.empty_card_section>
          </.async_result>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp summary_with_trends(analytics, project_id, {start_datetime, end_datetime} = period) do
    summary = analytics.summary(project_id, DatePicker.period_opts(period))

    previous =
      start_datetime
      |> previous_period(end_datetime)
      |> DatePicker.period_opts()
      |> then(&analytics.summary(project_id, &1))

    trends =
      for phase <- Analytics.phases(), into: %{} do
        {phase,
         Map.new(summary[phase], fn {stat, value} ->
           previous_value = previous[phase][stat]
           {stat, trend(numeric(previous_value), numeric(value))}
         end)}
      end

    Map.put(summary, :trends, trends)
  end

  defp usage_with_trends(project, {start_datetime, end_datetime}) do
    usage = Usage.project_usage(project, start_datetime, DateTime.add(end_datetime, 1))
    {previous_start, previous_end} = previous_period(start_datetime, end_datetime)
    previous = Usage.project_usage(project, previous_start, previous_end)

    Map.merge(usage, %{
      executions_trend: trend(previous.executions, usage.executions),
      execution_ms_trend: trend(previous.execution_ms, usage.execution_ms)
    })
  end

  defp param(params, key, allowed, default \\ nil) do
    value = params[key]
    if value in allowed, do: value, else: default || hd(allowed)
  end

  defp stat(type), do: String.to_existing_atom(type)

  defp phase_value(summary, phase, type), do: duration(summary[phase][stat(type)])

  defp phase_metrics(summary, phase) do
    Map.new(summary[phase], fn {stat, value} -> {stat, duration(value)} end)
  end

  defp phase_title(:queue, "p99"), do: dgettext("dashboard_builds", "p99 queue time")
  defp phase_title(:queue, "p90"), do: dgettext("dashboard_builds", "p90 queue time")
  defp phase_title(:queue, "p50"), do: dgettext("dashboard_builds", "p50 queue time")
  defp phase_title(:queue, _), do: dgettext("dashboard_builds", "Avg. queue time")
  defp phase_title(:execution, "p99"), do: dgettext("dashboard_builds", "p99 execution time")
  defp phase_title(:execution, "p90"), do: dgettext("dashboard_builds", "p90 execution time")
  defp phase_title(:execution, "p50"), do: dgettext("dashboard_builds", "p50 execution time")
  defp phase_title(:execution, _), do: dgettext("dashboard_builds", "Avg. execution time")

  defp legend_color("avg"), do: "secondary"
  defp legend_color(type), do: type

  defp duration(nil), do: dgettext("dashboard_builds", "Not recorded")
  defp duration(value), do: DateFormatter.format_duration_from_milliseconds(value)

  defp period_selection(params) do
    %{preset: preset, period: {first, last}} = DatePicker.date_picker_params(params, "analytics")
    now = DateTime.truncate(DateTime.utc_now(), :second)
    last = if DateTime.after?(last, now), do: now, else: last
    first = if DateTime.diff(last, first, :day) >= 90, do: DateTime.add(last, -89, :day), else: first

    if DateTime.before?(first, last) do
      %{
        preset: if(preset in ~w(last-24-hours last-7-days last-30-days), do: preset, else: "custom"),
        period: {first, last}
      }
    else
      DatePicker.date_picker_params(%{}, "analytics")
    end
  end

  defp sort_path(%{sort_by: sort_by, sort_order: sort_order} = assigns, column) do
    order = if sort_by == column and sort_order == "desc", do: "asc", else: "desc"
    patch_path(assigns, %{"invocations-sort-by" => column, "invocations-sort-order" => order, "page" => nil})
  end

  defp sort_label("duration"), do: dgettext("dashboard_builds", "Duration")
  defp sort_label("actions"), do: dgettext("dashboard_builds", "Remote actions")
  defp sort_label("execution"), do: dgettext("dashboard_builds", "Avg. execution")
  defp sort_label("execution-p50"), do: dgettext("dashboard_builds", "p50 execution")
  defp sort_label("execution-p90"), do: dgettext("dashboard_builds", "p90 execution")
  defp sort_label("status"), do: dgettext("dashboard_builds", "Status")
  defp sort_label(_ran_at), do: dgettext("dashboard_builds", "Ran at")

  defp sort_order(%{sort_by: column, sort_order: order}, column), do: order
  defp sort_order(_assigns, _column), do: nil

  defp available_filters do
    [
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_projects", "Status"),
        type: :option,
        options: ["success", "failure"],
        options_display_names: %{
          "success" => dgettext("dashboard_projects", "Succeeded"),
          "failure" => dgettext("dashboard_projects", "Failed")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "command",
        field: :command,
        display_name: dgettext("dashboard_projects", "Command"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "target_patterns",
        field: :target_patterns,
        display_name: dgettext("dashboard_projects", "Targets"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "actions",
        field: :actions,
        display_name: dgettext("dashboard_builds", "Remote actions"),
        type: :number,
        operator: :>=,
        value: nil
      }
    ]
  end

  defp patch_path(%{uri: uri} = assigns, changes),
    do: list_path(assigns, (uri.query || "") |> URI.decode_query() |> Map.merge(changes))

  defp list_path(%{selected_account: account, selected_project: project}, params) do
    query =
      Map.reject(params, fn {key, value} -> is_nil(value) or (value == "" and !String.starts_with?(key, "filter_")) end)

    "/#{account.name}/#{project.name}/remote-execution?" <> URI.encode_query(query)
  end

  defp replace_query(socket, changes, assigns) do
    url = patch_path(socket.assigns, changes)

    socket
    |> assign(assigns)
    |> assign(:uri, url |> URI.new!() |> Map.put(:path, nil))
    |> push_event("replace-url", %{url: url})
  end

  # Profile timings load and fail apart from usage, so a slow diagnostics query
  # never hides the usage widgets.
  defp timings_state(summary, series) do
    cond do
      summary.failed || series.failed -> :failed
      summary.ok? and series.ok? -> :ready
      true -> :loading
    end
  end

  defp widgets(_once?), do: @usage_widgets ++ @profile_widgets

  # Bazel reads remote phases from published profiles; Struo from the
  # gateway's action records, which name the Struo run.
  defp analytics(true = _once?), do: RunAnalytics
  defp analytics(false), do: Analytics

  defp invocation_path(%{once?: true} = assigns, row) do
    if row[:run],
      do: ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/runs/#{row.invocation_id}"
  end

  defp invocation_path(assigns, row),
    do:
      ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{row.invocation_id}?tab=remote-execution"

  defp invocation_label(row, false = _once?), do: requested_command(row)
  defp invocation_label(%{command: command}, true) when is_binary(command) and command != "", do: command

  # A run whose events never arrived has no command; name it by its ID and target.
  defp invocation_label(%{invocation_id: id, target_patterns: targets}, true),
    do: Enum.join([dgettext("dashboard_builds", "Run %{id}", id: String.slice(id, 0, 16)) | Enum.take(targets, 1)], " · ")

  # Running invocations lead the first page of the unfiltered table. The
  # table's search and filters match finished invocations' fields, so they
  # hide running ones.
  defp running_rows(%AsyncResult{ok?: true, result: running}, 1 = _page, %{search: "", active_filters: []}), do: running

  defp running_rows(_running, _page, _assigns), do: []

  defp running_command(%{command: nil, invocation_id: invocation_id}),
    do: dgettext("dashboard_builds", "Invocation %{id}", id: String.slice(invocation_id, 0, 8))

  defp running_command(invocation), do: requested_command(invocation)

  defp running_actions(%{running: nil}), do: "–"

  defp running_actions(%{running: running, queued: queued}),
    do: dgettext("dashboard_builds", "%{running} running · %{queued} queued", running: running, queued: queued)

  defp usage_chart_options(usage, widget) do
    format = if widget == "executions", do: "{value}", else: "fn:formatMilliseconds"

    %{
      legend: chart_legend(),
      grid: %{left: "0.4%", right: "2%", top: 12, bottom: 56},
      xAxis: chart_x_axis(usage.dates, usage.granularity),
      yAxis: chart_y_axis(format),
      tooltip: chart_tooltip(format, usage.granularity)
    }
  end

  defp usage_chart_series(usage, "executions"),
    do: [
      line(
        usage.dates,
        Enum.map(usage.series, & &1.executions),
        "var:noora-chart-primary",
        dgettext("dashboard_builds", "Executions")
      )
    ]

  defp usage_chart_series(usage, _execution_time),
    do: [
      line(
        usage.dates,
        Enum.map(usage.series, & &1.execution_ms),
        "var:noora-chart-primary",
        dgettext("dashboard_builds", "Total execution time")
      )
    ]

  defp has_data?(series, widget), do: Enum.any?(series[String.to_existing_atom(widget)].avg, &is_number/1)

  defp chart_options(series) do
    %{
      legend: chart_legend(),
      grid: %{left: "0.4%", right: "2%", top: 12, bottom: 56},
      xAxis: chart_x_axis(series.dates, series.granularity),
      yAxis: chart_y_axis("fn:formatMilliseconds"),
      tooltip: chart_tooltip("fn:formatMilliseconds", series.granularity)
    }
  end

  defp chart_series(series, widget) do
    values = series[String.to_existing_atom(widget)]

    [
      line(series.dates, values.avg, "var:noora-chart-secondary", dgettext("dashboard_projects", "Average")),
      line(series.dates, values.p99, "var:noora-chart-p99", "p99"),
      line(series.dates, values.p90, "var:noora-chart-p90", "p90"),
      line(series.dates, values.p50, "var:noora-chart-p50", "p50")
    ]
  end

  # Matches the Builds analytics lines. Periods without measurements are gaps
  # bridged by the line, never plotted as zero; a lone sample still shows a dot.
  defp line(dates, values, color, name) do
    %{
      color: color,
      data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1),
      name: name,
      type: "line",
      smooth: 0.1,
      connectNulls: true,
      symbol: if(Enum.count(values, &(is_number(&1) and &1 > 0)) <= 1, do: "circle", else: "none")
    }
  end

  defp chart_legend do
    %{
      left: "left",
      top: "bottom",
      orient: "horizontal",
      textStyle: %{
        color: "var:noora-surface-label-secondary",
        fontFamily: "monospace",
        fontWeight: 400,
        fontSize: 10,
        lineHeight: 12
      },
      icon:
        "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
      itemWidth: 8,
      itemHeight: 4
    }
  end
end
