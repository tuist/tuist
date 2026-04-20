defmodule Tuist.Operator.OrchardWorkerPoolController do
  @moduledoc """
  Bonny controller for the `OrchardWorkerPool` CRD.

  Bridges k8s CR events to the existing Phoenix reconciliation logic:

    * On `:add` / `:modify` — upsert a matching `Tuist.Runners.OrchardWorkerPool`
      row from the CR spec, then call `Tuist.Runners.Reconciler.reconcile/1`.
    * On `:delete` — disable the pool, drain any active workers, then delete
      the DB row.
    * On `:reconcile` (periodic) — re-run the reconciler and mirror observed
      state back into `status`.

  Most real work lives in `Tuist.Runners.Reconciler`; this module is the thin
  k8s-to-Phoenix adapter.
  """
  use Bonny.ControllerV2

  alias Tuist.Runners
  alias Tuist.Runners.Reconciler

  require Logger

  step(:handle_event)
  step(:reflect_status)

  @impl Bonny.ControllerV2
  def rbac_rules do
    [
      %{
        apiGroups: ["tuist.dev"],
        resources: ["orchardworkerpools", "orchardworkerpools/status"],
        verbs: ["*"]
      }
    ]
  end

  def handle_event(%Bonny.Axn{action: action, resource: resource} = axn, _opts)
      when action in [:add, :modify, :reconcile] do
    with {:ok, pool} <- upsert_pool_from_cr(resource),
         {:ok, _result} <- Reconciler.reconcile(pool.id) do
      Pluggable.Token.assign(axn, :pool_id, pool.id)
    else
      {:error, reason} ->
        Logger.error("OrchardWorkerPool reconcile failed: #{inspect(reason)}")
        Bonny.Axn.failure_event(axn, reason: "ReconcileFailed", message: format(reason))
    end
  end

  def handle_event(%Bonny.Axn{action: :delete, resource: resource} = axn, _opts) do
    account_id = get_in(resource, ["spec", "accountId"])
    name = get_in(resource, ["metadata", "name"])

    case Runners.get_orchard_worker_pool_by_account_and_name(account_id, name) do
      {:ok, pool} ->
        {:ok, pool} = Runners.update_orchard_worker_pool_spec(pool, %{enabled: false})
        _ = Reconciler.reconcile(pool.id)
        {:ok, _} = Runners.delete_orchard_worker_pool(pool)
        Bonny.Axn.success_event(axn, reason: "Deleted", message: "Pool deleted and drained")

      {:error, :not_found} ->
        axn
    end
  end

  def reflect_status(%Bonny.Axn{assigns: %{pool_id: pool_id}} = axn, _opts) do
    case Runners.get_orchard_worker_pool(pool_id) do
      {:ok, pool} ->
        current_size = Runners.count_active_workers_in_pool(pool.id)

        axn
        |> Bonny.Axn.update_status(fn status ->
          status
          |> Map.put("phase", pool_phase(pool, current_size))
          |> Map.put("currentSize", current_size)
          |> Map.put(
            "lastReconciledAt",
            pool.last_reconciled_at && DateTime.to_iso8601(pool.last_reconciled_at)
          )
        end)
        |> Bonny.Axn.set_condition(
          "Ready",
          ready_status(pool, current_size),
          "Current: #{current_size}/#{pool.desired_size}"
        )

      _ ->
        axn
    end
  end

  def reflect_status(axn, _opts), do: axn

  defp upsert_pool_from_cr(resource) do
    account_id = get_in(resource, ["spec", "accountId"])
    name = get_in(resource, ["metadata", "name"])

    spec_attrs = %{
      enabled: Map.get(resource["spec"], "enabled", true),
      desired_size: Map.fetch!(resource["spec"], "desiredSize"),
      scaleway_zone: Map.fetch!(resource["spec"], "scalewayZone"),
      scaleway_server_type: Map.fetch!(resource["spec"], "scalewayServerType"),
      scaleway_os: Map.fetch!(resource["spec"], "scalewayOs")
    }

    case Runners.get_orchard_worker_pool_by_account_and_name(account_id, name) do
      {:ok, pool} ->
        Runners.update_orchard_worker_pool_spec(pool, spec_attrs)

      {:error, :not_found} ->
        Runners.create_orchard_worker_pool(Map.merge(spec_attrs, %{account_id: account_id, name: name}))
    end
  end

  defp pool_phase(%{enabled: false}, _current_size), do: "Disabled"
  defp pool_phase(%{desired_size: d}, current) when current == d, do: "Ready"
  defp pool_phase(_pool, _current), do: "Reconciling"

  defp ready_status(%{enabled: false}, _), do: "False"
  defp ready_status(%{desired_size: d}, current) when current == d, do: "True"
  defp ready_status(_, _), do: "False"

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
