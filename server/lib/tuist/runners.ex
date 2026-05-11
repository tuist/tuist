defmodule Tuist.Runners do
  @moduledoc """
  Customer-facing GitHub Actions runners on Tuist's Mac mini fleet.

  Architecture:

    * **One CRD: `RunnerPool`.** Helm-rendered, one CR per fleet
      (today one). Its `spec.minWarm` equals the fleet's host count,
      so every host always carries either a warm Pod (idle, polling)
      or a Pod running a customer job.
    * **The Go controller's `RunnerPoolReconciler`** maintains the
      pool's Pods + per-Pod ServiceAccounts directly via owner
      refs — no `RunnerAssignment` CRD. Pod terminates → reconciler
      boots a replacement.
    * **`accounts.runner_max_concurrent`** is the only per-customer
      knob. 0 = runners disabled; N>0 = at most N concurrent.
    * **Postgres `runner_dispatch_queue`** is the burst queue. The
      webhook enqueues; warm Pods polling the dispatch endpoint
      claim with `FOR UPDATE SKIP LOCKED`. Per-account depth
      ceiling (`4 × max_concurrent`) keeps any one customer from
      flooding the table.

  `max_concurrent` enforcement: at *claim* time, the dispatch
  endpoint counts Pods labeled `tuist.dev/runner-pool-owner=<account-name>`
  via a K8s LIST, builds the set of accounts at cap, and asks the
  queue for the oldest entry whose account isn't in that set.
  Capped customers' rows wait in the queue until their count drops.

  GitHub repo-scoping is currently delegated to the GitHub default
  runner group (id=1), which allows every repo in the org. A
  per-account `runner_group_id` is a follow-up once multi-tenant
  onboarding makes per-repo scoping necessary.
  """

  alias Tuist.Accounts
  alias Tuist.GitHub.App, as: GitHubApp
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.DispatchQueue

  require Logger

  @pool_label "tuist.dev/runner-pool"
  @owner_label "tuist.dev/runner-pool-owner"
  @account_label "tuist.dev/runner-account"

  @doc """
  Claims the oldest eligible queue entry for the SA's fleet and
  mints a JIT for the entry's account. Stamps the polling Pod
  with owner labels so subsequent `max_concurrent` counts include
  it.

  Returns `{:ok, %{jit, account}}` on success.

  Error cases the web layer translates to HTTP responses:
    * `{:error, :no_work_yet}` — queue empty (or all pending
      accounts at cap); warm Pod keeps polling.
    * `{:error, :not_found}` — SA gone (raced with GC).
    * `{:error, :no_pool_label}` — SA missing the fleet label.
    * `{:error, :unknown_account}` — claimed entry's account
      went away.
    * `{:error, :github_mint_failed}` — GitHub refused the JIT.
    * `{:error, :not_in_cluster}` — server not running in-cluster.
  """
  def dispatch_for_sa(namespace, sa_name) when is_binary(namespace) and is_binary(sa_name) do
    with {:ok, sa} <- K8sClient.get_service_account(namespace, sa_name),
         {:ok, fleet_name} <- pool_label(sa) do
      ineligible = ineligible_account_ids(namespace)

      case DispatchQueue.claim_oldest_eligible(fleet_name, ineligible) do
        {:ok, %{account_id: account_id}} ->
          serve_claim(namespace, sa_name, account_id)

        {:error, :empty} ->
          {:error, :no_work_yet}

        {:error, reason} ->
          Logger.warning("runners: claim_oldest_eligible failed", reason: inspect(reason))
          {:error, :no_work_yet}
      end
    end
  end

  defp serve_claim(namespace, sa_name, account_id) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} ->
        pod_name = pod_name_from_sa(sa_name)

        with :ok <- stamp_owner_labels(namespace, pod_name, account),
             {:ok, jit, runner_name} <- mint_jit(account, sa_name) do
          Logger.info("runners: dispatched",
            account: account.name,
            sa: sa_name,
            runner: runner_name
          )

          {:ok, %{jit: jit, account: account, runner_name: runner_name}}
        end

      {:error, :not_found} ->
        Logger.warning("runners: claimed entry has no account row", account_id: account_id)
        {:error, :unknown_account}
    end
  end

  # Builds the set of account ids whose owners are currently at
  # `runner_max_concurrent`. The dispatch queue's claim query
  # skips entries belonging to any of these. Returns `[]` when the
  # LIST fails (fail-open so an apiserver blip doesn't stall the
  # queue; a capped customer may briefly exceed by one).
  defp ineligible_account_ids(namespace) do
    case K8sClient.list_pods(namespace, @owner_label) do
      {:ok, pods} ->
        owner_counts =
          pods
          |> Enum.filter(&active_pod?/1)
          |> Enum.frequencies_by(&owner_from_pod/1)
          |> Map.delete(nil)

        if owner_counts == %{} do
          []
        else
          owner_counts
          |> Map.keys()
          |> Enum.reduce([], fn owner, acc ->
            case Accounts.get_account_by_handle(owner) do
              %{id: id, runner_max_concurrent: cap}
              when is_integer(cap) and cap > 0 ->
                if Map.get(owner_counts, owner, 0) >= cap, do: [id | acc], else: acc

              _ ->
                acc
            end
          end)
        end

      {:error, reason} ->
        Logger.warning("runners: list_pods failed; ineligibility check open",
          reason: inspect(reason)
        )

        []
    end
  end

  defp active_pod?(%{"status" => %{"phase" => phase}, "metadata" => meta}) do
    deletion_ts = Map.get(meta, "deletionTimestamp")
    phase not in ["Succeeded", "Failed"] and is_nil(deletion_ts)
  end

  defp active_pod?(%{"metadata" => meta}) do
    is_nil(Map.get(meta, "deletionTimestamp"))
  end

  defp active_pod?(_), do: false

  defp owner_from_pod(%{"metadata" => %{"labels" => labels}}) when is_map(labels) do
    Map.get(labels, @owner_label)
  end

  defp owner_from_pod(_), do: nil

  defp stamp_owner_labels(namespace, pod_name, account) do
    patch = %{
      "metadata" => %{
        "labels" => %{
          @owner_label => account.name,
          @account_label => Integer.to_string(account.id)
        }
      }
    }

    case K8sClient.patch_pod(namespace, pod_name, patch) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("runners: pod label stamp failed; max_concurrent count may undercount",
          pod: pod_name,
          reason: inspect(reason)
        )

        # Continue — the runner still serves the job; counts are
        # eventually consistent.
        :ok
    end
  end

  defp mint_jit(account, sa_name) do
    runner_name = "tuist-#{account.name}-#{sa_name}"

    with {:ok, installation_id} <- GitHubApp.get_installation_id_for_org(account.name),
         {:ok, %{encoded_jit_config: jit, runner_name: runner_name}} <-
           GitHubClient.generate_jit_config(installation_id, account.name, %{
             name: runner_name,
             labels: ["self-hosted", "macOS", "ARM64", Dispatch.dispatch_label()]
           }) do
      {:ok, jit, runner_name}
    else
      {:error, :not_installed} ->
        Logger.warning("runners: GitHub App not installed on org", account: account.name)
        {:error, :github_mint_failed}

      {:error, reason} ->
        Logger.error("runners: GitHub jit mint failed",
          account: account.name,
          reason: inspect(reason)
        )

        {:error, :github_mint_failed}
    end
  end

  defp pool_label(%{"metadata" => %{"labels" => labels}}) when is_map(labels) do
    case Map.get(labels, @pool_label) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, :no_pool_label}
    end
  end

  defp pool_label(_), do: {:error, :no_pool_label}

  # The polling Pod's name. The controller's podtemplate stamps
  # Pods + SAs with the same name, so the SA name IS the Pod name.
  defp pod_name_from_sa(sa_name), do: sa_name
end
