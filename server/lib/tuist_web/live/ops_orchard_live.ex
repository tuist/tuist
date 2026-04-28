defmodule TuistWeb.OpsOrchardLive do
  @moduledoc """
  Operator dashboard for the embedded Orchard control plane. Shows the
  Mac mini fleet (workers + their last-seen heartbeats) and the VMs
  scheduled across them.

  Real-time updates flow over Phoenix.PubSub: `Tuist.Orchard` broadcasts
  `:vm_changed` / `:vm_deleted` whenever the controller updates state,
  and we also re-poll workers every 10s so the LastSeen column stays
  fresh between explicit events.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Orchard
  alias Tuist.Orchard.Worker

  @worker_offline_seconds 60
  @poll_interval_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tuist.PubSub, "orchard:vms")
      Process.send_after(self(), :poll, @poll_interval_ms)
    end

    {:ok,
     socket
     |> assign_fleet()
     |> assign(:head_title, "Orchard Operations · Tuist")}
  end

  @impl true
  def handle_info({:vm_changed, _vm}, socket) do
    {:noreply, assign_fleet(socket)}
  end

  def handle_info({:vm_deleted, _vm}, socket) do
    {:noreply, assign_fleet(socket)}
  end

  def handle_info(:poll, socket) do
    Process.send_after(self(), :poll, @poll_interval_ms)
    {:noreply, assign_fleet(socket)}
  end

  defp assign_fleet(socket) do
    workers = Orchard.list_workers()
    vms = Orchard.list_vms()

    socket
    |> assign(:workers, workers)
    |> assign(:vms, vms)
    |> assign(:online_workers, Enum.count(workers, &online?/1))
    |> assign(:running_vms, Enum.count(vms, &(&1.status == "running")))
    |> assign(:pending_vms, Enum.count(vms, &(&1.status == "pending")))
    |> assign(:failed_vms, Enum.count(vms, &(&1.status == "failed")))
  end

  defp online?(%Worker{} = w), do: not Worker.offline?(w, @worker_offline_seconds)

  defp worker_status(%Worker{} = w) do
    if Worker.offline?(w, @worker_offline_seconds), do: "Offline", else: "Online"
  end

  defp format_last_seen(nil), do: "never"

  defp format_last_seen(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 0 -> DateTime.to_iso8601(dt)
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> DateTime.to_iso8601(dt)
    end
  end

  defp assigned_or_requested(0, requested), do: requested
  defp assigned_or_requested(assigned, _requested), do: assigned
end
