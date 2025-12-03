defmodule TuistWeb.CILive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection

  alias Noora.Filter
  alias Tuist.CI
  alias Tuist.Projects
  alias Tuist.Projects.VCSConnection
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project}} = socket) do
    project = Tuist.Repo.preload(project, :vcs_connection)

    socket =
      socket
      |> assign(:selected_project, project)
      |> assign(
        :head_title,
        "#{gettext("CI")} · #{Projects.get_project_slug_from_id(project.id)} · Tuist"
      )
      |> assign(:available_filters, define_filters())

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    uri = URI.new!("?" <> URI.encode_query(params))

    sort_by = params["sort-by"] || "started-at"
    sort_order = params["sort-order"] || "desc"

    {
      :noreply,
      socket
      |> assign(:uri, uri)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign_job_runs(params)
    }
  end

  defp define_filters do
    [
      %Filter.Filter{
        id: "workflow_name",
        field: :workflow_name,
        display_name: gettext("Workflow"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "runner_machine",
        field: :runner_machine,
        display_name: gettext("Machine"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "runner_configuration",
        field: :runner_configuration,
        display_name: gettext("Configuration"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: gettext("Status"),
        type: :option,
        options: ["success", "failure", "running", "pending", "cancelled"],
        options_display_names: %{
          "success" => gettext("Success"),
          "failure" => gettext("Failed"),
          "running" => gettext("Running"),
          "pending" => gettext("Pending"),
          "cancelled" => gettext("Cancelled")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: gettext("Branch"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  defp assign_job_runs(
         %{
           assigns: %{
             selected_project: project,
             sort_by: sort_by,
             sort_order: sort_order,
             available_filters: available_filters
           }
         } = socket,
         params
       ) do
    filters = Filter.Operations.decode_filters_from_query(params, available_filters)
    search = params["search"] || ""

    base_flop_filters = [
      %{field: :project_id, op: :==, value: project.id}
    ]

    filter_flop_filters = Filter.Operations.convert_filters_to_flop(filters)

    search_filters =
      if search == "" do
        []
      else
        [%{field: :workflow_name, op: :ilike_and, value: search}]
      end

    flop_filters = base_flop_filters ++ filter_flop_filters ++ search_filters

    order_by =
      case sort_by do
        "started-at" -> :started_at
        "duration" -> :duration_ms
        "workflow" -> :workflow_name
        _ -> :started_at
      end

    order_direction = String.to_atom(sort_order)

    options = %{
      filters: flop_filters,
      order_by: [order_by],
      order_directions: [order_direction]
    }

    options =
      cond do
        !is_nil(params["after"]) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, params["after"])

        !is_nil(params["before"]) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, params["before"])

        true ->
          Map.put(options, :first, 20)
      end

    {job_runs, job_runs_meta} = CI.list_job_runs(options)

    socket
    |> assign(:active_filters, filters)
    |> assign(:job_runs, job_runs)
    |> assign(:job_runs_meta, job_runs_meta)
    |> assign(:search, search)
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/ci?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/ci?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event(
        "search",
        %{"search" => search},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query =
      uri.query
      |> Query.put("search", search)
      |> Query.drop("before")
      |> Query.drop("after")

    socket =
      push_patch(
        socket,
        to: "/#{selected_account.name}/#{selected_project.name}/ci?#{query}",
        replace: true
      )

    {:noreply, socket}
  end

  def sort_dropdown_patch(sort_by, uri) do
    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("sort-by", sort_by)
      |> Map.delete("after")
      |> Map.delete("before")
      |> Map.delete("sort-order")

    "?#{URI.encode_query(query_params)}"
  end

  def sort_label("started-at"), do: gettext("Ran at")
  def sort_label("duration"), do: gettext("Duration")
  def sort_label("workflow"), do: gettext("Workflow")
  def sort_label(_), do: gettext("Ran at")

  def job_status(status) do
    case status do
      "success" -> "success"
      "failure" -> "error"
      "running" -> "running"
      "pending" -> "pending"
      "cancelled" -> "cancelled"
      _ -> "pending"
    end
  end

  def format_duration(nil), do: "-"

  def format_duration(duration_ms) do
    DateFormatter.format_duration_from_milliseconds(duration_ms)
  end

  def format_commit_sha(sha) when is_binary(sha) do
    String.slice(sha, 0, 12)
  end

  def format_commit_sha(_), do: "-"

  def branch_url(%VCSConnection{provider: :github, repository_full_handle: handle}, branch) when is_binary(branch) do
    "https://github.com/#{handle}/tree/#{branch}"
  end

  def branch_url(_, _), do: nil

  def commit_url(%VCSConnection{provider: :github, repository_full_handle: handle}, sha) when is_binary(sha) do
    "https://github.com/#{handle}/commit/#{sha}"
  end

  def commit_url(_, _), do: nil

  attr(:status, :string, required: true)

  def status_indicator(%{status: "success"} = assigns) do
    ~H"""
    <div data-status="success"><.circle_check /></div>
    """
  end

  def status_indicator(%{status: "error"} = assigns) do
    ~H"""
    <div data-status="error"><.alert_circle /></div>
    """
  end

  def status_indicator(%{status: "running"} = assigns) do
    ~H"""
    <div data-status="running"><.circle_dashed /></div>
    """
  end

  def status_indicator(%{status: "pending"} = assigns) do
    ~H"""
    <div data-status="pending"><.clock_hour_4 /></div>
    """
  end

  def status_indicator(%{status: "cancelled"} = assigns) do
    ~H"""
    <div data-status="cancelled"><.cancel /></div>
    """
  end

  def status_indicator(assigns) do
    ~H"""
    <div data-status="unknown"><.clock_hour_4 /></div>
    """
  end
end
