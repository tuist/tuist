defmodule TuistWeb.RunnersLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Authorization
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter

  @widget_limit 5

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    workflows = Jobs.list_workflows_for_account(selected_account.id, limit: @widget_limit)
    recent_jobs = Jobs.list_for_account(selected_account.id, limit: @widget_limit)
    counts = Jobs.status_counts(selected_account.id)

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{dgettext("dashboard_runners", "Runners")} · #{selected_account.name} · Tuist"
     )
     |> assign(:workflows, workflows)
     |> assign(:recent_jobs, recent_jobs)
     |> assign(:status_counts, counts)}
  end

  def total_jobs(counts) when is_map(counts) do
    Enum.reduce(counts, 0, fn {_, v}, acc -> acc + v end)
  end

  def in_progress_jobs(counts) when is_map(counts) do
    Map.get(counts, "queued", 0) + Map.get(counts, "claimed", 0) + Map.get(counts, "running", 0)
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

  def status_badge_props("queued"), do: %{label: dgettext("dashboard_runners", "Queued"), status: "warning"}
  def status_badge_props("claimed"), do: %{label: dgettext("dashboard_runners", "Claimed"), status: "in_progress"}
  def status_badge_props("running"), do: %{label: dgettext("dashboard_runners", "Running"), status: "in_progress"}
  def status_badge_props("completed"), do: %{label: dgettext("dashboard_runners", "Completed"), status: "success"}
  def status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), status: "warning"}

  def conclusion_badge_props("success"), do: %{label: dgettext("dashboard_runners", "Success"), status: "success"}
  def conclusion_badge_props("failure"), do: %{label: dgettext("dashboard_runners", "Failure"), status: "error"}
  def conclusion_badge_props("cancelled"), do: %{label: dgettext("dashboard_runners", "Cancelled"), status: "warning"}
  def conclusion_badge_props("skipped"), do: %{label: dgettext("dashboard_runners", "Skipped"), status: "warning"}
  def conclusion_badge_props(_), do: nil

  def from_now(%DateTime{} = ts), do: DateFormatter.from_now(ts)
  def from_now(_), do: "–"

  def from_now_or_dash(%DateTime{year: 1970}), do: "–"
  def from_now_or_dash(%DateTime{} = ts), do: DateFormatter.from_now(ts)
  def from_now_or_dash(_), do: "–"

  def widget_empty_label, do: dgettext("dashboard_runners", "No jobs yet")
end
