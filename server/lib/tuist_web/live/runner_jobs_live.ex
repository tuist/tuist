defmodule TuistWeb.RunnerJobsLive do
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
       "#{dgettext("dashboard_runners", "Jobs")} · #{selected_account.name} · Tuist"
     )
     |> assign(:available_filters, available_filters())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status = parse_status(params["status"])
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    {:noreply,
     socket
     |> assign(:selected_status, status)
     |> assign(:active_filters, filters)
     |> assign_jobs()}
  end

  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/jobs?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  @impl true
  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(to: ~p"/#{socket.assigns.selected_account.name}/runners/jobs?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  defp parse_status(s) when s in ["queued", "claimed", "running", "completed"], do: s
  defp parse_status(_), do: nil

  defp assign_jobs(
         %{
           assigns: %{
             selected_account: account,
             selected_status: status,
             active_filters: filters
           }
         } = socket
       ) do
    opts =
      [limit: @page_size, status: status]
      |> add_filter_opt(filters, "repository", :repo)
      |> add_filter_opt(filters, "workflow", :workflow_name)
      |> add_filter_opt(filters, "job", :job_name)
      |> add_filter_opt(filters, "branch", :head_branch)
      |> add_conclusion_opt(filters)

    jobs = Jobs.list_for_account(account.id, opts)
    counts = Jobs.status_counts(account.id)

    socket
    |> assign(:jobs, jobs)
    |> assign(:status_counts, counts)
  end

  defp add_filter_opt(opts, filters, filter_id, opt_key) do
    case Enum.find(filters, &(&1.id == filter_id)) do
      %{value: value} when is_binary(value) and value != "" -> Keyword.put(opts, opt_key, value)
      _ -> opts
    end
  end

  defp add_conclusion_opt(opts, filters) do
    case Enum.find(filters, &(&1.id == "conclusion")) do
      %{value: value} when not is_nil(value) ->
        Keyword.put(opts, :conclusion, to_string(value))

      _ ->
        opts
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
        id: "job",
        field: :job_name,
        display_name: dgettext("dashboard_runners", "Job"),
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
      },
      %Filter.Filter{
        id: "conclusion",
        field: :conclusion,
        display_name: dgettext("dashboard_runners", "Conclusion"),
        type: :option,
        options: [:success, :failure, :cancelled, :skipped],
        options_display_names: %{
          success: dgettext("dashboard_runners", "Success"),
          failure: dgettext("dashboard_runners", "Failure"),
          cancelled: dgettext("dashboard_runners", "Cancelled"),
          skipped: dgettext("dashboard_runners", "Skipped")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  def status_badge_props("queued"), do: %{label: dgettext("dashboard_runners", "Queued"), status: "warning"}
  def status_badge_props("claimed"), do: %{label: dgettext("dashboard_runners", "Claimed"), status: "in_progress"}
  def status_badge_props("running"), do: %{label: dgettext("dashboard_runners", "Running"), status: "in_progress"}
  def status_badge_props("completed"), do: %{label: dgettext("dashboard_runners", "Completed"), status: "success"}
  def status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), status: "warning"}

  def conclusion_badge_props("success"), do: %{label: dgettext("dashboard_runners", "Success"), status: "success"}
  def conclusion_badge_props("failure"), do: %{label: dgettext("dashboard_runners", "Failure"), status: "error"}
  def conclusion_badge_props("cancelled"), do: %{label: dgettext("dashboard_runners", "Cancelled"), status: "warning"}
  def conclusion_badge_props("skipped"), do: %{label: dgettext("dashboard_runners", "Skipped"), status: "warning"}

  def conclusion_badge_props(other) when is_binary(other) and other != "",
    do: %{label: String.capitalize(other), status: "warning"}

  def conclusion_badge_props(_), do: nil

  @doc """
  Picks the most informative duration for a row depending on its
  status:
    * queued — time spent waiting in the queue
    * claimed — time since claimed (waiting for the runner to mint)
    * running — time the runner has been executing
    * completed — total run duration (started → completed)
  """
  def duration_ms(%{status: "queued", enqueued_at: enqueued}), do: ms_since(enqueued)
  def duration_ms(%{status: "claimed", claimed_at: claimed}), do: ms_since(claimed)
  def duration_ms(%{status: "running", started_at: started}), do: ms_since(started)

  def duration_ms(%{status: "completed", started_at: started, completed_at: completed}) do
    cond do
      is_nil(started) or epoch?(started) -> 0
      is_nil(completed) or epoch?(completed) -> 0
      true -> DateTime.diff(completed, started, :millisecond)
    end
  end

  def duration_ms(_), do: 0

  defp ms_since(nil), do: 0

  defp ms_since(%DateTime{} = ts) do
    if epoch?(ts), do: 0, else: DateTime.diff(DateTime.utc_now(), ts, :millisecond)
  end

  defp epoch?(%DateTime{year: 1970, month: 1, day: 1}), do: true
  defp epoch?(_), do: false

  def format_duration(ms) when is_integer(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(ms)
  def format_duration(_), do: "–"

  def short_sha(""), do: "–"
  def short_sha(nil), do: "–"
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)
end
