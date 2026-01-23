defmodule TuistWeb.TestCaseLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Helpers.FailureMessage
  import TuistWeb.Helpers.VCSLinks
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Accounts
  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias Tuist.Slack
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @table_page_size 20

  def mount(
        %{"test_case_id" => test_case_id} = _params,
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    project = Tuist.Repo.preload(project, :vcs_connection)

    test_case_detail =
      case Runs.get_test_case_by_id(test_case_id) do
        {:ok, test_case} -> test_case
        {:error, :not_found} -> raise NotFoundError, dgettext("dashboard_tests", "Test case not found.")
      end

    # Verify project ownership
    if test_case_detail.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_tests", "Test case not found.")
    end

    slug = "#{account.name}/#{project.name}"

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    socket =
      socket
      |> assign(:selected_project, project)
      |> assign(:test_case_id, test_case_id)
      |> assign(:test_case_detail, test_case_detail)
      |> assign(:head_title, "#{test_case_detail.name} · #{slug} · Tuist")
      |> assign(:available_filters, define_filters(project))

    {:ok, socket}
  end

  defp define_filters(project) do
    filters = [
      %Filter.Filter{
        id: "status",
        field: "status",
        display_name: dgettext("dashboard_tests", "Status"),
        type: :option,
        options: ["success", "failure", "skipped"],
        options_display_names: %{
          "success" => dgettext("dashboard_tests", "Passed"),
          "failure" => dgettext("dashboard_tests", "Failed"),
          "skipped" => dgettext("dashboard_tests", "Skipped")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "duration",
        field: "duration",
        display_name: dgettext("dashboard_tests", "Duration"),
        type: :number,
        operator: :>,
        value: ""
      }
    ]

    if Accounts.organization?(project.account) do
      {:ok, organization} = Accounts.get_organization_by_id(project.account.organization_id)
      users = Accounts.get_organization_members(organization)

      filters ++
        [
          %Filter.Filter{
            id: "ran_by",
            field: :ran_by,
            display_name: dgettext("dashboard_tests", "Ran by"),
            type: :option,
            options: [:ci] ++ Enum.map(users, fn user -> user.account.id end),
            options_display_names:
              Map.merge(
                %{ci: dgettext("dashboard_tests", "CI")},
                Map.new(users, fn user -> {user.account.id, user.account.name} end)
              ),
            operator: :==,
            value: nil
          }
        ]
    else
      filters
    end
  end

  def handle_params(params, _uri, socket) do
    uri = URI.new!("?" <> URI.encode_query(params))
    selected_tab = params["tab"] || "overview"

    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:selected_tab, selected_tab)
      |> assign_analytics()
      |> assign_test_case_runs(params)
      |> assign_history_tab(selected_tab)
      |> assign_overview_history()

    {:noreply, socket}
  end

  defp assign_history_tab(socket, "history") do
    test_case_id = socket.assigns.test_case_id
    page = 1

    {events, meta} = Runs.list_test_case_events(test_case_id, %{page: page, page_size: 20})

    socket
    |> assign(:history_events, events)
    |> assign(:history_meta, meta)
    |> assign(:history_page, page)
  end

  defp assign_history_tab(socket, _other_tab) do
    socket
    |> assign(:history_events, [])
    |> assign(:history_meta, %Flop.Meta{
      total_count: 0,
      total_pages: 0,
      current_page: 1,
      page_size: 20,
      has_next_page?: false
    })
    |> assign(:history_page, 1)
  end

  defp assign_overview_history(socket) do
    test_case_id = socket.assigns.test_case_id

    {events, meta} = Runs.list_test_case_events(test_case_id, %{page: 1, page_size: 3})

    has_more = meta.total_count > 3

    socket
    |> assign(:overview_history_events, events)
    |> assign(:overview_history_has_more, has_more)
  end

  defp refresh_history_events(%{assigns: %{selected_tab: "history", test_case_id: test_case_id}} = socket) do
    {events, meta} = Runs.list_test_case_events(test_case_id, %{page: 1, page_size: 20})

    socket
    |> assign(:history_events, events)
    |> assign(:history_meta, meta)
    |> assign(:history_page, 1)
    |> assign_overview_history()
  end

  defp refresh_history_events(socket) do
    assign_overview_history(socket)
  end

  def handle_event(
        "search-test-case-runs",
        %{"search" => search},
        %{assigns: %{selected_account: account, selected_project: project, test_case_id: test_case_id, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?#{uri.query |> Query.put("search", search) |> Query.drop("page")}"
      )

    {:noreply, socket}
  end

  def handle_event(
        "add_filter",
        %{"value" => filter_id},
        %{assigns: %{selected_account: account, selected_project: project, test_case_id: test_case_id}} = socket
      ) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event(
        "update_filter",
        params,
        %{assigns: %{selected_account: account, selected_project: project, test_case_id: test_case_id}} = socket
      ) do
    updated_query_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?#{updated_query_params}")
     |> push_event("close-dropdown", %{all: true})
     |> push_event("close-popover", %{all: true})}
  end

  def handle_event(
        "unmark-as-flaky",
        _params,
        %{assigns: %{test_case_id: test_case_id, test_case_detail: test_case_detail, current_user: current_user}} = socket
      ) do
    {:ok, updated_test_case} =
      Runs.update_test_case(
        test_case_id,
        %{is_flaky: false},
        %{type: :user, id: current_user.account.id}
      )

    {:noreply,
     socket
     |> assign(:test_case_detail, %{test_case_detail | is_flaky: updated_test_case.is_flaky})
     |> assign(:flaky_runs_grouped, [])
     |> refresh_history_events()}
  end

  def handle_event(
        "mark-as-flaky",
        _params,
        %{
          assigns: %{
            test_case_id: test_case_id,
            test_case_detail: test_case_detail,
            selected_project: project,
            current_user: current_user
          }
        } = socket
      ) do
    {:ok, updated_test_case} =
      Runs.update_test_case(
        test_case_id,
        %{is_flaky: true},
        %{type: :user, id: current_user.account.id}
      )

    test_case_detail = %{test_case_detail | is_flaky: updated_test_case.is_flaky}

    {test_case_detail, was_auto_quarantined} =
      if project.auto_quarantine_flaky_tests do
        {:ok, quarantined_test_case} =
          Runs.update_test_case(
            test_case_id,
            %{is_quarantined: true},
            %{type: :user, id: current_user.account.id}
          )

        {%{test_case_detail | is_quarantined: quarantined_test_case.is_quarantined}, true}
      else
        {test_case_detail, false}
      end

    # Send Slack notification for manual flaky marking
    send_manual_flaky_alert(project, updated_test_case, current_user, was_auto_quarantined)

    {:noreply,
     socket
     |> assign(:test_case_detail, test_case_detail)
     |> refresh_history_events()}
  end

  def handle_event(
        "quarantine",
        _params,
        %{assigns: %{test_case_id: test_case_id, test_case_detail: test_case_detail, current_user: current_user}} = socket
      ) do
    {:ok, updated_test_case} =
      Runs.update_test_case(
        test_case_id,
        %{is_quarantined: true},
        %{type: :user, id: current_user.account.id}
      )

    {:noreply,
     socket
     |> assign(:test_case_detail, %{test_case_detail | is_quarantined: updated_test_case.is_quarantined})
     |> refresh_history_events()}
  end

  def handle_event(
        "unquarantine",
        _params,
        %{assigns: %{test_case_id: test_case_id, test_case_detail: test_case_detail, current_user: current_user}} = socket
      ) do
    {:ok, updated_test_case} =
      Runs.update_test_case(
        test_case_id,
        %{is_quarantined: false},
        %{type: :user, id: current_user.account.id}
      )

    {:noreply,
     socket
     |> assign(:test_case_detail, %{test_case_detail | is_quarantined: updated_test_case.is_quarantined})
     |> refresh_history_events()}
  end

  def handle_event(
        "load-more-history",
        _params,
        %{assigns: %{test_case_id: test_case_id, history_page: current_page, history_events: current_events}} = socket
      ) do
    next_page = current_page + 1
    {new_events, meta} = Runs.list_test_case_events(test_case_id, %{page: next_page, page_size: 20})

    {:noreply,
     socket
     |> assign(:history_events, current_events ++ new_events)
     |> assign(:history_meta, meta)
     |> assign(:history_page, next_page)}
  end

  def handle_info({:test_created, %{name: "test"}}, socket) do
    socket =
      socket
      |> assign_analytics()
      |> assign_test_case_runs(URI.decode_query(socket.assigns.uri.query))

    {:noreply, socket}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(
         %{assigns: %{selected_project: project, test_case_id: test_case_id, test_case_detail: test_case_detail}} = socket
       ) do
    [reliability, analytics, flakiness_rate, {flaky_runs_grouped, flaky_runs_meta}] =
      Task.await_many(
        [
          Task.async(fn ->
            Analytics.test_case_reliability_by_id(
              test_case_id,
              project.default_branch
            )
          end),
          Task.async(fn ->
            Analytics.test_case_analytics_by_id(test_case_id)
          end),
          Task.async(fn ->
            Analytics.get_test_case_flakiness_rate(test_case_detail)
          end),
          Task.async(fn ->
            Runs.list_flaky_runs_for_test_case(test_case_id)
          end)
        ],
        30_000
      )

    socket
    |> assign(:reliability, reliability)
    |> assign(:analytics, analytics)
    |> assign(:flakiness_rate, flakiness_rate)
    |> assign(:flaky_runs_grouped, flaky_runs_grouped)
    |> assign(:flaky_runs_meta, flaky_runs_meta)
  end

  defp assign_test_case_runs(
         %{assigns: %{test_case_id: test_case_id, available_filters: available_filters}} = socket,
         params
       ) do
    page = parse_page(params["page"])
    search = params["search"] || ""
    sort_by = params["sort_by"] || "ran_at"
    sort_order = params["sort_order"] || "desc"

    filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    flop_filters = build_flop_filters(filters, search)

    order_directions = [if(sort_order == "asc", do: :asc, else: :desc)]
    order_by = [String.to_existing_atom(sort_by)]

    {test_case_runs, meta} =
      Runs.list_test_case_runs_by_test_case_id(
        test_case_id,
        %{
          page: page,
          page_size: @table_page_size,
          filters: flop_filters,
          order_by: order_by,
          order_directions: order_directions
        }
      )

    socket
    |> assign(:test_case_runs, test_case_runs)
    |> assign(:test_case_runs_meta, meta)
    |> assign(:test_case_runs_page, page)
    |> assign(:test_case_runs_search, search)
    |> assign(:test_case_runs_sort_by, sort_by)
    |> assign(:test_case_runs_sort_order, sort_order)
    |> assign(:active_filters, filters)
  end

  defp build_flop_filters(filters, search) do
    base_filters =
      Enum.flat_map(filters, fn
        %{id: "ran_by", value: :ci, operator: :==} ->
          [%{field: :is_ci, op: :==, value: true}]

        %{id: "ran_by", value: value, operator: :==} when not is_nil(value) ->
          [%{field: :account_id, op: :==, value: value}]

        %{field: field, operator: op, value: value} when not is_nil(value) and value != "" ->
          [%{field: field, op: op, value: value}]

        _ ->
          []
      end)

    if search == "" do
      base_filters
    else
      base_filters ++ [%{field: :scheme, op: :ilike_and, value: search}]
    end
  end

  defp parse_page(nil), do: 1
  defp parse_page(page) when is_binary(page), do: String.to_integer(page)
  defp parse_page(page) when is_integer(page), do: page

  defp sort_by_patch(uri, sort_by) do
    "?#{uri.query |> Query.put("sort_by", sort_by) |> Query.drop("page")}"
  end

  defp sort_icon("asc"), do: "square_rounded_arrow_up"
  defp sort_icon("desc"), do: "square_rounded_arrow_down"

  defp toggle_sort_order("asc"), do: "desc"
  defp toggle_sort_order("desc"), do: "asc"

  defp column_sort_patch(assigns, column) do
    new_order =
      if assigns.test_case_runs_sort_by == column do
        toggle_sort_order(assigns.test_case_runs_sort_order)
      else
        "desc"
      end

    "?#{assigns.uri.query |> Query.put("sort_by", column) |> Query.put("sort_order", new_order) |> Query.drop("page")}"
  end

  defp send_manual_flaky_alert(project, test_case, user, was_auto_quarantined) do
    if project.flaky_test_alerts_enabled and project.flaky_test_alerts_slack_channel_id do
      :ok = Slack.send_manual_flaky_test_alert(project, test_case, user, was_auto_quarantined)
    end

    :ok
  end

  defp event_icon("first_run"), do: "info_circle"
  defp event_icon("marked_flaky"), do: "alert_triangle"
  defp event_icon("unmarked_flaky"), do: "circle_check"
  defp event_icon("quarantined"), do: "lock"
  defp event_icon("unquarantined"), do: "lock_open_2"
  defp event_icon(_), do: "info_circle"

  defp event_color("first_run"), do: "primary"
  defp event_color("marked_flaky"), do: "warning"
  defp event_color("unmarked_flaky"), do: "success"
  defp event_color("quarantined"), do: "destructive"
  defp event_color("unquarantined"), do: "information"
  defp event_color(_), do: "primary"

  defp event_title("first_run"), do: dgettext("dashboard_tests", "First run of this test")
  defp event_title("marked_flaky"), do: dgettext("dashboard_tests", "Marked as flaky")
  defp event_title("unmarked_flaky"), do: dgettext("dashboard_tests", "Unmarked as flaky")
  defp event_title("quarantined"), do: dgettext("dashboard_tests", "Marked as quarantined")
  defp event_title("unquarantined"), do: dgettext("dashboard_tests", "Marked as unquarantined")
  defp event_title(_), do: dgettext("dashboard_tests", "Event")

  defp format_event_subtitle(%{event_type: "first_run"}), do: nil

  defp format_event_subtitle(%{actor: nil}), do: dgettext("dashboard_tests", "Automatically by Tuist")

  defp format_event_subtitle(%{actor: actor}), do: dgettext("dashboard_tests", "Manually by @%{name}", name: actor.name)
end
