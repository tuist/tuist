defmodule Pulse.Alerting.Worker do
  @moduledoc "Opt-in disposable native evaluator. Membership reduces work; rule-head CAS enforces correctness."
  use Pulse.Runtime.GenServer

  alias Pulse.Alerting.{Canonical, Evaluator, Recording, Repository}
  alias Pulse.Alerting.Membership
  alias Pulse.Alerting.Notifier
  alias Pulse.Alerting.Tasks
  alias Pulse.Auth.Issuer
  alias Pulse.Runtime
  alias Pulse.Runtime.GenServer
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    cache = :ets.new(:alert_budget_skips, [:set, :public])
    opts = Keyword.put(opts, :budget_skip_cache, cache)
    config = Keyword.get(opts, :store_config, Runtime.get_env(:pulse, S3, [])) |> Map.new()
    group = {:alerting, Canonical.hash(Enum.map([:bucket, :endpoint, :region], &Map.get(config, &1)))}
    :ok = :pg.join(Membership, group, self())
    send(self(), :tick)
    {:ok, %{opts: opts, group: group, task: nil, last_pass: nil}}
  end

  @impl true
  def handle_info(:tick, %{task: nil} = state) do
    nodes = :pg.get_members(Membership, state.group) |> Enum.map(&node/1) |> Enum.uniq()

    task =
      Task.Supervisor.async_nolink(Tasks, fn ->
        Process.flag(:max_heap_size, %{size: 8_000_000, kill: true, error_logger: false, include_shared_binaries: true})
        run_once(state.opts, nodes)
      end)

    {:noreply, %{state | task: task.ref}}
  end

  def handle_info({ref, result}, %{task: ref} = state) do
    Process.demonitor(ref, [:flush])
    schedule(state.opts)
    {:noreply, %{state | task: nil, last_pass: result}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: ref} = state) do
    schedule(state.opts)
    {:noreply, %{state | task: nil, last_pass: {:error, :pass_failed}}}
  end

  def handle_info(_, state), do: {:noreply, state}

  def run_once(opts, nodes) do
    store = Keyword.get(opts, :object_store, Pulse.ObjectStore)
    config = Keyword.get(opts, :store_config, Runtime.get_env(:pulse, S3, [])) |> Map.new()

    repo_opts = [
      store: store,
      store_config: config,
      evaluation_enabled: Keyword.get(opts, :evaluation_enabled, true),
      notifications_enabled: Keyword.get(opts, :notifications_enabled, false),
      budget_skip_cache: Keyword.get(opts, :budget_skip_cache)
    ]

    with {:ok, prefixes} <- store.list_prefixes(config, "tenants/") do
      total = Enum.reduce(prefixes, 0, &evaluate_tenant(&1, &2, nodes, repo_opts))

      :telemetry.execute([:pulse, :alerting, :pass], %{rules: total}, %{})
      {:ok, total}
    end
  end

  defp evaluate_tenant(prefix, total, nodes, opts) do
    tenant = prefix |> String.trim_trailing("/") |> String.split("/") |> List.last()

    # Suspended and deleted tenants are not evaluated, whether the tenant
    # registry or the issuer status list marks them.
    with true <- Pulse.Tenants.active?(tenant),
         false <- Issuer.suspended?(tenant),
         {:ok, ids} <- Repository.list(tenant, opts) do
      Enum.reduce(ids, total, &evaluate_owned(tenant, &1, &2, nodes, opts))
    else
      _ -> total
    end
  end

  defp evaluate_owned(tenant, id, count, nodes, opts) do
    if Pulse.Rendezvous.owner(["alerting", tenant, id], nodes) == node() do
      actor = %{
        tenant: tenant,
        id: "pulse-evaluator",
        type: "service",
        capabilities: ~w(alert:read alert:evaluate alert:import alert:record)
      }

      if Keyword.get(opts, :evaluation_enabled, true), do: evaluate_and_publish(actor, tenant, id, opts)

      if Keyword.get(opts, :notifications_enabled, false), do: Notifier.run_once(tenant, id, opts)
      count + 1
    else
      count
    end
  end

  defp evaluate_and_publish(actor, tenant, id, opts) do
    Recording.drain(tenant, id, opts)

    # Publish a fresh recording at once instead of one poll later.
    case Evaluator.evaluate(actor, id, Keyword.put(opts, :require_recording_drained, true)) do
      {:ok, %{"recording_pending" => pending}} when pending > 0 -> Recording.drain(tenant, id, opts)
      _ -> :ok
    end
  end

  defp schedule(opts), do: Process.send_after(self(), :tick, Keyword.get(opts, :poll_interval_ms, 5000))
end
