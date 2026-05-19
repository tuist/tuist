defmodule TuistWeb.RunnerWorkflowsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection

  alias Noora.Filter
  alias Tuist.Authorization
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter

  @page_size 50

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{dgettext("dashboard_runners", "Workflows")} · #{selected_account.name} · Tuist"
     )
     |> assign(:available_filters, available_filters())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    {:noreply,
     socket
     |> assign(:active_filters, filters)
     |> assign_workflows()}
  end

  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/workflows?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  @impl true
  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/workflows?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  defp assign_workflows(
         %{assigns: %{selected_account: account, active_filters: filters}} = socket
       ) do
    opts =
      [limit: @page_size]
      |> add_filter_opt(filters, "repository", :repo)
      |> add_filter_opt(filters, "workflow", :workflow_name)
      |> add_filter_opt(filters, "branch", :head_branch)

    workflows = Jobs.list_workflows_for_account(account.id, opts)
    assign(socket, :workflows, workflows)
  end

  defp add_filter_opt(opts, filters, filter_id, opt_key) do
    case Enum.find(filters, &(&1.id == filter_id)) do
      %{value: value} when is_binary(value) and value != "" -> Keyword.put(opts, opt_key, value)
      _ -> opts
    end
  end

  defp available_filters do
    [
      %Filter.Filter{
        id: "repository",
        field: :repo,
        display_name: dgettext("dashboard_runners", "Repository"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "workflow",
        field: :workflow_name,
        display_name: dgettext("dashboard_runners", "Workflow"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "branch",
        field: :head_branch,
        display_name: dgettext("dashboard_runners", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end

  def success_rate(%{success_count: success, total_jobs: total}) when total > 0 do
    rate = success / total * 100

    rate
    |> Float.round(1)
    |> :erlang.float_to_binary(decimals: 1)
    |> Kernel.<>("%")
  end

  def success_rate(_), do: "–"

  def format_duration_ms(value) when is_number(value) and value > 0,
    do: DateFormatter.format_duration_from_milliseconds(round(value))

  def format_duration_ms(_), do: "–"

  def from_now_or_dash(%DateTime{year: 1970}), do: "–"
  def from_now_or_dash(%DateTime{} = ts), do: DateFormatter.from_now(ts)
  def from_now_or_dash(_), do: "–"
end
