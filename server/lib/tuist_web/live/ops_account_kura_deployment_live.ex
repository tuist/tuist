defmodule TuistWeb.OpsAccountKuraDeploymentLive do
  @moduledoc """
  Detail view for a single Kura deployment attempt: status, error
  message, and a Grafana Explore link for backing Kubernetes logs.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Server

  @poll_interval_ms 2_000
  @grafana_base_url "https://tuist.grafana.net/explore"
  @grafana_logs_datasource "grafanacloud-tuist-logs"

  @impl true
  def mount(%{"id" => account_id, "deployment_id" => deployment_id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(account_id)) do
      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, dgettext("dashboard", "Account not found.")) |> push_navigate(to: ~p"/ops/accounts")}

      {:ok, account} ->
        case Kura.get_deployment(account.id, deployment_id) do
          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, dgettext("dashboard", "Deployment not found."))
             |> push_navigate(to: ~p"/ops/accounts/#{account.id}")}

          {:ok, deployment} ->
            if connected?(socket), do: schedule_poll(deployment)

            {:ok,
             socket
             |> assign(:head_title, "#{dgettext("dashboard", "Deployment")} · Tuist Ops")
             |> assign(:account, account)
             |> assign(:deployment, deployment)
             |> assign(:grafana_logs_url, grafana_logs_url(deployment))}
        end
    end
  end

  @impl true
  def handle_info(:poll, socket) do
    deployment =
      case Kura.get_deployment(socket.assigns.account.id, socket.assigns.deployment.id) do
        {:ok, deployment} -> deployment
        {:error, :not_found} -> socket.assigns.deployment
      end

    if connected?(socket), do: schedule_poll(deployment)

    {:noreply, socket |> assign(:deployment, deployment) |> assign(:grafana_logs_url, grafana_logs_url(deployment))}
  end

  defp schedule_poll(%{status: status}) when status in [:pending, :running] do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp schedule_poll(_), do: :ok

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      {_n, _rest} -> 0
      :error -> 0
    end
  end

  def deployment_status_label(:pending), do: dgettext("dashboard", "Pending")
  def deployment_status_label(:running), do: dgettext("dashboard", "Running")
  def deployment_status_label(:succeeded), do: dgettext("dashboard", "Succeeded")
  def deployment_status_label(:failed), do: dgettext("dashboard", "Failed")
  def deployment_status_label(:cancelled), do: dgettext("dashboard", "Cancelled")

  def deployment_status_color(:pending), do: "neutral"
  def deployment_status_color(:running), do: "information"
  def deployment_status_color(:succeeded), do: "success"
  def deployment_status_color(:failed), do: "destructive"
  def deployment_status_color(:cancelled), do: "warning"

  def format_time(nil), do: dgettext("dashboard", "None")
  def format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  defp grafana_logs_url(%Deployment{kura_server: %Server{provisioner_node_ref: ref}}) when is_binary(ref) do
    query = ~s({namespace="kura", app_kubernetes_io_instance="#{ref}"})

    left =
      JSON.encode!(%{
        "datasource" => @grafana_logs_datasource,
        "queries" => [
          %{
            "refId" => "A",
            "expr" => query
          }
        ],
        "range" => %{"from" => "now-6h", "to" => "now"}
      })

    @grafana_base_url <> "?" <> URI.encode_query(%{"orgId" => "1", "left" => left})
  end

  defp grafana_logs_url(_deployment), do: @grafana_base_url
end
