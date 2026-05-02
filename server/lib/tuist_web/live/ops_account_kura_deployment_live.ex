defmodule TuistWeb.OpsAccountKuraDeploymentLive do
  @moduledoc """
  Detail view for a single Kura deployment attempt: status, error
  message, and the live tail of `helm` / `rollout.sh` output streamed
  from ClickHouse. Polls every two seconds while the attempt is in a
  non-terminal state.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Kura

  @poll_interval_ms 2_000
  @batch_limit 1_000

  @impl true
  def mount(%{"id" => account_id, "deployment_id" => deployment_id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(account_id)) do
      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, "Account not found.") |> push_navigate(to: ~p"/ops/accounts")}

      {:ok, account} ->
        case Kura.get_deployment(account.id, deployment_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Deployment not found.")
             |> push_navigate(to: ~p"/ops/accounts/#{account.id}")}

          deployment ->
            if connected?(socket), do: schedule_poll(deployment)

            {:ok,
             socket
             |> assign(:head_title, "Deployment · Tuist Ops")
             |> assign(:account, account)
             |> assign(:deployment, deployment)
             |> assign(:log_lines, [])
             |> assign(:last_sequence, -1)
             |> refresh()}
        end
    end
  end

  @impl true
  def handle_info(:poll, socket) do
    socket = refresh(socket)
    if connected?(socket), do: schedule_poll(socket.assigns.deployment)
    {:noreply, socket}
  end

  defp schedule_poll(%{status: status}) when status in [:pending, :running] do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp schedule_poll(_), do: :ok

  defp refresh(socket) do
    deployment = Kura.get_deployment(socket.assigns.account.id, socket.assigns.deployment.id)

    new_lines =
      Kura.list_log_lines(deployment.id,
        limit: @batch_limit,
        after_sequence: socket.assigns.last_sequence
      )

    last_sequence =
      case List.last(new_lines) do
        nil -> socket.assigns.last_sequence
        %{sequence: seq} -> seq
      end

    socket
    |> assign(:deployment, deployment)
    |> assign(:log_lines, socket.assigns.log_lines ++ new_lines)
    |> assign(:last_sequence, last_sequence)
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, _} -> n
      :error -> 0
    end
  end

  def deployment_status_label(:pending), do: "Pending"
  def deployment_status_label(:running), do: "Running"
  def deployment_status_label(:succeeded), do: "Succeeded"
  def deployment_status_label(:failed), do: "Failed"
  def deployment_status_label(:cancelled), do: "Cancelled"

  def deployment_status_color(:pending), do: "neutral"
  def deployment_status_color(:running), do: "information"
  def deployment_status_color(:succeeded), do: "success"
  def deployment_status_color(:failed), do: "destructive"
  def deployment_status_color(:cancelled), do: "warning"

  def format_time(nil), do: "—"
  def format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  def empty_logs_message(status) when status in [:pending, :running],
    do: "No log output yet. Polling every two seconds while the deployment is pending or running."

  def empty_logs_message(:succeeded), do: "The deployment finished without producing any captured log output."

  def empty_logs_message(:failed),
    do: "The deployment failed before producing any captured log output. See the error message above for details."

  def empty_logs_message(:cancelled), do: "The deployment was cancelled before producing any log output."

  def empty_logs_message(_), do: "No log output captured."
end
