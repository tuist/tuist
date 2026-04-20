defmodule TuistWeb.OpsOrchardWorkersLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Runners
  alias Tuist.Runners.Workers.DeprovisionOrchardWorkerWorker
  alias Tuist.Runners.Workers.ReconcilePoolsWorker

  @refresh_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval_ms, :refresh)
    end

    {:ok,
     socket
     |> assign_fleet()
     |> assign(:head_title, "Runner Fleet · Tuist")}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, assign_fleet(socket)}

  @impl true
  def handle_event("reconcile_pool", %{"id" => pool_id}, socket) do
    {:ok, _job} =
      %{"orchard_worker_pool_id" => pool_id}
      |> ReconcilePoolsWorker.new()
      |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Reconciliation triggered")}
  end

  @impl true
  def handle_event("deprovision_worker", %{"id" => id}, socket) do
    case Runners.get_orchard_worker(id) do
      {:ok, worker} ->
        {:ok, _} = Runners.update_orchard_worker(worker, %{status: :draining})

        {:ok, _job} =
          %{"orchard_worker_id" => worker.id}
          |> DeprovisionOrchardWorkerWorker.new()
          |> Oban.insert()

        {:noreply, assign_fleet(socket)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_worker", %{"id" => id}, socket) do
    with {:ok, worker} <- Runners.get_orchard_worker(id),
         true <- worker.status in [:terminated, :failed],
         {:ok, _} <- Runners.delete_orchard_worker(worker) do
      {:noreply, assign_fleet(socket)}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Only terminated or failed workers can be deleted")}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  defp assign_fleet(socket) do
    pools = Runners.list_orchard_worker_pools()

    pools_with_counts =
      Enum.map(pools, fn pool ->
        Map.put(pool, :current_size, Runners.count_active_workers_in_pool(pool.id))
      end)

    socket
    |> assign(:pools, pools_with_counts)
    |> assign(:workers, Runners.list_orchard_workers())
  end

  def humanize_status(status), do: status |> Atom.to_string() |> String.capitalize()

  def format_datetime(nil), do: "--"
  def format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
