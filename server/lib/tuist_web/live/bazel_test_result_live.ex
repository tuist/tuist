defmodule TuistWeb.BazelTestResultLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Helpers.VCSLinks

  alias Noora.Filter
  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.BazelInvocationLive
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @cache_page_size 20

  def mount(
        %{"test_result_id" => test_result_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    project = Tuist.Repo.preload(project, vcs_connection: :github_app_installation)

    case Bazel.get_test_result(project.id, test_result_id) do
      {:ok, test_result} ->
        invocation =
          case Bazel.get_invocation(project.id, test_result.invocation_id) do
            {:ok, invocation} -> invocation
            {:error, :not_found} -> nil
          end

        {:ok,
         socket
         |> assign(:selected_project, project)
         |> assign(:test_result, test_result)
         |> assign(:invocation, invocation)
         |> assign(:has_logs, Bazel.invocation_logs_present?(project.id, test_result.invocation_id))
         |> assign(:selected_tab, "overview")
         |> assign(:logs, [])
         |> assign(:log_output, "")
         |> assign(:cache, ReapiCache.invocation_summary(project.id, test_result.invocation_id))
         |> assign(:available_filters, BazelInvocationLive.cache_filters())
         |> assign(:cache_events, [])
         |> assign(:cache_timeline_events, [])
         |> assign(:cache_outcome_counts, %{"hit" => 0, "miss" => 0, "write" => 0})
         |> assign(:cache_filter, "")
         |> assign(:active_cache_filters, [])
         |> assign(:cache_current_page, 1)
         |> assign(:cache_total_pages, 0)
         |> assign(:cache_sort_by, "observed")
         |> assign(:cache_sort_order, "desc")
         |> assign(:critical_path_expanded, false)
         |> assign(:head_title, "#{test_result.target_label} · #{account.name}/#{project.name} · Tuist")
         |> assign(OpenGraph.og_image_assigns("tests"))}

      {:error, :not_found} ->
        raise NotFoundError, dgettext("dashboard_projects", "Bazel test result not found.")
    end
  end

  def handle_params(params, uri, socket) do
    selected_tab = selected_tab(params)
    project = socket.assigns.selected_project
    test_result = socket.assigns.test_result

    logs =
      if selected_tab == "logs" do
        Bazel.recent_invocation_logs(project.id, test_result.invocation_id)
      else
        []
      end

    {cache_events, cache_timeline_events, cache_outcome_counts, cache_meta, active_cache_filters, cache_sort_by,
     cache_sort_order} =
      if selected_tab == "cache" do
        load_cache_events(project.id, test_result.invocation_id, params, socket.assigns.available_filters)
      else
        {[], [], %{"hit" => 0, "miss" => 0, "write" => 0}, %{current_page: 1, total_pages: 0}, [], "observed", "desc"}
      end

    {:noreply,
     socket
     |> assign(:selected_tab, selected_tab)
     |> assign(:logs, logs)
     |> assign(:log_output, Enum.map_join(logs, "", & &1.message))
     |> assign(:uri, URI.new!(uri))
     |> assign(:cache_events, cache_events)
     |> assign(:cache_timeline_events, cache_timeline_events)
     |> assign(:cache_outcome_counts, cache_outcome_counts)
     |> assign(:cache_filter, params["cache-filter"] || "")
     |> assign(:cache_current_page, cache_meta.current_page)
     |> assign(:cache_total_pages, cache_meta.total_pages)
     |> assign(:active_cache_filters, active_cache_filters)
     |> assign(:cache_sort_by, cache_sort_by)
     |> assign(:cache_sort_order, cache_sort_order)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: cache_path(socket, updated_params))
    |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
    |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})
    |> then(&{:noreply, &1})
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: cache_path(socket, updated_params))
    |> push_event("close-dropdown", %{id: "all", all: true})
    |> push_event("close-popover", %{id: "all", all: true})
    |> then(&{:noreply, &1})
  end

  def handle_event("search_cache_requests", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("cache-filter", search)
      |> Query.put("page", "1")

    {:noreply, push_patch(socket, to: "#{detail_path(socket.assigns)}?#{query}")}
  end

  def handle_event("toggle_critical_path", _params, socket) do
    {:noreply, update(socket, :critical_path_expanded, &(not &1))}
  end

  def render(assigns) do
    ~H"""
    <div id="bazel-test-result" class="bazel-invocation">
      <.button
        label={dgettext("dashboard_projects", "Tests")}
        data-part="back-button"
        variant="secondary"
        size="medium"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests"}
      >
        <:icon_left><.icon name="arrow_left" /></:icon_left>
      </.button>
      <div data-part="header">
        <div data-part="title-group">
          <div data-part="title">
            <div data-part={status_icon_part(@test_result.status)}>
              <div data-part="icon">
                <.circle_check :if={@test_result.status == "success"} />
                <.alert_circle :if={@test_result.status == "failure"} />
                <.alert_triangle :if={@test_result.status == "flaky"} />
                <.alert_hexagon :if={@test_result.status == "skipped"} />
              </div>
            </div>
            <h1 data-part="label">{@test_result.target_label}</h1>
            <.badge
              :if={@invocation}
              label={"bazel " <> @invocation.command}
              color="information"
              style="light-fill"
              size="large"
            />
            <.badge
              :if={@test_result.status in ["flaky", "skipped"]}
              label={status_label(@test_result.status)}
              color={status_badge_color(@test_result.status)}
              style="light-fill"
              size="large"
            />
          </div>
          <.link_button
            :if={@invocation}
            data-part="invocation-link"
            navigate={
              ~p"/#{@selected_account.name}/#{@selected_project.name}/invocations/#{@test_result.invocation_id}"
            }
            label={dgettext("dashboard_projects", "Test invocation")}
            size="large"
            underline
          >
            <:icon_left><.versions /></:icon_left>
          </.link_button>
        </div>
        <div :if={@has_logs} data-part="actions">
          <.button
            label={dgettext("dashboard_projects", "Download logs")}
            href={download_path(assigns)}
            variant="secondary"
            size="medium"
          >
            <:icon_left><.download /></:icon_left>
          </.button>
        </div>
      </div>
      <.tab_menu_horizontal data-part="tabs">
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Overview")}
          patch={tab_path(assigns, "overview")}
          selected={@selected_tab == "overview"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Command")}
          patch={tab_path(assigns, "command")}
          selected={@selected_tab == "command"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Cache")}
          patch={tab_path(assigns, "cache")}
          selected={@selected_tab == "cache"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Logs")}
          patch={tab_path(assigns, "logs")}
          selected={@selected_tab == "logs"}
        />
      </.tab_menu_horizontal>
      <div :if={@selected_tab == "overview"} data-part="tab-panel">
        <BazelInvocationLive.build_metrics :if={@invocation} invocation={@invocation} />
        <.card
          title={dgettext("dashboard_projects", "Details")}
          icon="chart_arcs"
          data-part="test-details-card"
        >
          <.card_section data-part="invocation-details-section">
            <div data-part="metadata-grid">
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Status")}</div>
                  <.badge
                    label={status_label(@test_result.status)}
                    color={status_badge_color(@test_result.status)}
                    style="fill"
                    size="large"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Duration")}</div>
                  <span data-part="label">
                    <.history />
                    {DateFormatter.format_duration_from_milliseconds(@test_result.duration_ms)}
                  </span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Finished")}</div>
                  <span data-part="label">
                    {DateFormatter.format_with_timezone(@test_result.finished_at, nil)}
                  </span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Attempts")}</div>
                  <span data-part="label">{@test_result.attempt_count}</span>
                </div>
              </div>
              <div data-part="metadata-row">
                <div data-part="metadata" data-field="target">
                  <div data-part="title">{dgettext("dashboard_projects", "Target")}</div>
                  <code data-part="command">{@test_result.target_label}</code>
                </div>
                <div
                  :if={@invocation && @invocation.bazel_version != ""}
                  data-part="metadata"
                  data-field="bazel-version"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Bazel version")}</div>
                  <code data-part="command">{@invocation.bazel_version}</code>
                </div>
                <div
                  :if={@invocation && @invocation.compilation_mode != ""}
                  data-part="metadata"
                  data-field="compilation-mode"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Mode")}</div>
                  <code data-part="command">{@invocation.compilation_mode}</code>
                </div>
                <div
                  :if={@invocation && @invocation.client_platform != "unknown"}
                  data-part="metadata"
                  data-field="environment"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Environment")}</div>
                  <span data-part="label">{BazelInvocationLive.client_platform_label(
                    @invocation.client_platform
                  )}</span>
                </div>
                <div
                  :if={@invocation && @invocation.configurations != []}
                  data-part="metadata"
                  data-field="configurations"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Configurations")}</div>
                  <div data-part="badges">
                    <.badge
                      :for={configuration <- @invocation.configurations}
                      label={configuration}
                      color="information"
                      style="light-fill"
                      size="small"
                    />
                  </div>
                </div>
                <div
                  :if={@invocation}
                  data-part="metadata"
                  data-field="remote-services"
                  data-configuration-present={to_string(@invocation.configurations != [])}
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Remote services")}</div>
                  <div data-part="badges">
                    <.badge
                      :if={@invocation.remote_cache_enabled}
                      label={dgettext("dashboard_projects", "Remote cache")}
                      color="success"
                      style="light-fill"
                      size="small"
                    />
                    <.badge
                      :if={@invocation.remote_execution_enabled}
                      label={dgettext("dashboard_projects", "Remote execution")}
                      color="success"
                      style="light-fill"
                      size="small"
                    />
                    <.badge
                      :if={
                        not @invocation.remote_cache_enabled and
                          not @invocation.remote_execution_enabled
                      }
                      label={dgettext("dashboard_projects", "Local")}
                      color="neutral"
                      style="light-fill"
                      size="small"
                    />
                  </div>
                </div>
              </div>
              <div data-part="metadata-row">
                <div :if={connected_to_repository?(@selected_project)} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Repository")}</div>
                  <.repository_link project={@selected_project} data-part="git-reference" />
                </div>
                <div :if={@invocation && @invocation.git_branch != ""} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Branch")}</div>
                  <.branch_link
                    project={@selected_project}
                    branch={@invocation.git_branch}
                    data-part="git-reference"
                  />
                </div>
                <div :if={@invocation && @invocation.git_commit_sha != ""} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Commit")}</div>
                  <.commit_link
                    project={@selected_project}
                    commit_sha={@invocation.git_commit_sha}
                    data-part="git-reference"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Invocation ID")}</div>
                  <code data-part="identifier">{@test_result.invocation_id}</code>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>
        <BazelInvocationLive.build_timeline
          :if={@invocation && Map.get(@invocation, :build_timeline_span_descriptions, []) != []}
          invocation={@invocation}
        />
        <BazelInvocationLive.critical_path
          :if={
            @invocation &&
              @invocation.critical_path_action_descriptions != []
          }
          invocation={@invocation}
          project={@selected_project}
          expanded={@critical_path_expanded}
        />
      </div>
      <div :if={@selected_tab == "command" and @invocation} data-part="tab-panel">
        <BazelInvocationLive.command_configuration invocation={@invocation} />
      </div>
      <div :if={@selected_tab == "cache"} data-part="tab-panel">
        <BazelInvocationLive.cache_tab
          cache={@cache}
          cache_events={@cache_events}
          cache_timeline_events={@cache_timeline_events}
          cache_outcome_counts={@cache_outcome_counts}
          cache_filter={@cache_filter}
          active_cache_filters={@active_cache_filters}
          available_filters={@available_filters}
          cache_current_page={@cache_current_page}
          cache_total_pages={@cache_total_pages}
          cache_sort_by={@cache_sort_by}
          cache_sort_order={@cache_sort_order}
          uri={@uri}
          path={detail_path(assigns)}
          remote_cache_enabled={(@invocation && @invocation.remote_cache_enabled) || false}
          table_id="bazel-test-cache-events-table"
          filter_id="bazel-test-cache-filter-dropdown"
          widget_id_prefix="bazel-test-cache"
          search_id="bazel-test-cache-search"
        />
      </div>
      <div :if={@selected_tab == "logs"} data-part="tab-panel">
        <BazelInvocationLive.logs_card log_output={@log_output} has_logs={@has_logs} />
      </div>
    </div>
    """
  end

  defp status_label("success"), do: dgettext("dashboard_projects", "Succeeded")
  defp status_label("failure"), do: dgettext("dashboard_projects", "Failed")
  defp status_label("flaky"), do: dgettext("dashboard_projects", "Flaky")
  defp status_label(_), do: dgettext("dashboard_projects", "Skipped")
  defp status_badge_color("success"), do: "success"
  defp status_badge_color("failure"), do: "destructive"
  defp status_badge_color("flaky"), do: "attention"
  defp status_badge_color(_), do: "warning"
  defp status_icon_part("success"), do: "badge-success"
  defp status_icon_part("failure"), do: "badge-failure"
  defp status_icon_part("flaky"), do: "badge-flaky"
  defp status_icon_part(_), do: "badge-warning"

  defp connected_to_repository?(%{vcs_connection: %{provider: :github}}), do: true
  defp connected_to_repository?(_), do: false

  defp load_cache_events(project_id, invocation_id, params, available_filters) do
    cache_sort_by = params["cache-sort-by"] || "observed"
    cache_sort_order = params["cache-sort-order"] || "desc"

    active_cache_filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    {cache_events, cache_meta} =
      ReapiCache.list_invocation_cache_events(project_id, invocation_id, %{
        filters:
          cache_text_flop_filters(params["cache-filter"]) ++
            Filter.Operations.convert_filters_to_flop(active_cache_filters),
        order_by: [cache_sort_field(cache_sort_by)],
        order_directions: [cache_sort_direction(cache_sort_order)],
        page: parse_cache_page(params["page"]),
        page_size: @cache_page_size
      })

    cache_timeline_events = ReapiCache.list_invocation_cache_timeline_events(project_id, invocation_id)
    cache_outcome_counts = ReapiCache.invocation_cache_outcome_counts(project_id, invocation_id)

    {cache_events, cache_timeline_events, cache_outcome_counts, cache_meta, active_cache_filters, cache_sort_by,
     cache_sort_order}
  end

  defp cache_text_flop_filters(nil), do: []
  defp cache_text_flop_filters(""), do: []
  defp cache_text_flop_filters(search), do: [%{field: :action_mnemonic, op: :like, value: search}]

  defp cache_sort_field("outcome"), do: :outcome
  defp cache_sort_field("action"), do: :action_mnemonic
  defp cache_sort_field("target"), do: :target_label
  defp cache_sort_field("action-result"), do: :size
  defp cache_sort_field("latency"), do: :duration_ms
  defp cache_sort_field(_), do: :observed_at
  defp cache_sort_direction("asc"), do: :asc
  defp cache_sort_direction(_), do: :desc

  defp parse_cache_page(value) do
    case Integer.parse(value || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp selected_tab(%{"tab" => tab}) when tab in ["overview", "command", "cache", "logs"], do: tab
  defp selected_tab(_params), do: "overview"

  defp tab_path(assigns, tab), do: "#{detail_path(assigns)}?tab=#{tab}"

  defp detail_path(assigns),
    do: "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/tests/test-results/#{assigns.test_result.id}"

  defp cache_path(socket, params), do: "#{detail_path(socket.assigns)}?#{URI.encode_query(params)}"

  defp download_path(assigns),
    do:
      ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/invocations/#{assigns.test_result.invocation_id}/logs/download"
end
