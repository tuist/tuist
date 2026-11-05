defmodule Pulse.Loki.Tail do
  @moduledoc """
  Live log fan-out for Loki's `/loki/api/v1/tail`.

  Tailers register locally under their tenant. The first one starts the
  tenant's `Pulse.Loki.TailFollower` on this node. It follows shared log
  segments without requiring clustered instances and also receives this node's
  acknowledged appends directly (`publish/2`) for low latency. Exact overlap
  identities are bounded. Delivery is best-effort: late publication, failed
  polls or retirement can hide originals; event-time compaction settle is not
  a publication receipt.

  Each tailer selects records with the storage reference semantics
  (`Pulse.Storage.Memory.select_logs/2`) and runs the remaining LogQL
  pipeline itself, so ingest never evaluates queries on behalf of tailers.
  A tailer that cannot keep up drops whole batches and reports them as
  dropped entries; records are not replayed after a reconnect.
  """

  use Supervisor

  alias Pulse.Codec.NIF
  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Entry
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Pipeline
  alias Pulse.Loki.TailDelivery
  alias Pulse.Loki.TailFollower
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Storage.Memory

  # Names resolve in the caller, which carries the runtime instance.
  def start_link(_opts \\ []) do
    names =
      Enum.map(
        [__MODULE__.Registry, __MODULE__.AdmissionRegistry, __MODULE__.FollowerRegistry, __MODULE__.Followers],
        &Runtime.name/1
      )

    Supervisor.start_link(__MODULE__, names, name: Runtime.name(__MODULE__))
  end

  @impl true
  def init([registry, admission_registry, follower_registry, followers]) do
    Supervisor.init(
      [
        {Registry, keys: :duplicate, name: registry},
        {Registry, keys: :unique, name: admission_registry},
        {Registry, keys: :unique, name: follower_registry},
        {DynamicSupervisor, strategy: :one_for_one, name: followers}
      ],
      strategy: :one_for_all
    )
  end

  @doc """
  Register the calling process as one of `tenant`'s tailers on this node,
  unless it already has `max`, and make sure the tenant has a follower.
  Admission uses unique, process-owned slots, so simultaneous joins cannot
  overrun the limit. Slots are released on leave or caller termination.
  Returns the follower to monitor; its exit invalidates the live cursor.
  """
  @spec join(String.t(), pos_integer()) :: {:ok, pid()} | {:error, :too_many_tails | :tail_unavailable}
  def join(tenant, max) when is_integer(max) and max > 0 do
    if self() in tailers(tenant) do
      join_follower(tenant)
    else
      with :ok <- reserve(tenant, max) do
        {:ok, _} = Registry.register(registry(), {:tailer, tenant}, TailDelivery.new())
        join_follower(tenant)
      end
    end
  rescue
    ArgumentError -> unavailable(tenant)
  catch
    :exit, _reason -> unavailable(tenant)
  end

  defp join_follower(tenant) do
    case follower(tenant) do
      {:ok, _pid} = result -> result
      {:error, _reason} -> unavailable(tenant)
    end
  end

  defp reserve(tenant, max) do
    Enum.reduce_while(1..max, {:error, :too_many_tails}, fn slot, error ->
      case Registry.register(admission_registry(), {tenant, slot}, nil) do
        {:ok, _} -> {:halt, :ok}
        {:error, {:already_registered, _pid}} -> {:cont, error}
      end
    end)
  end

  defp unavailable(tenant) do
    leave(tenant)
    {:error, :tail_unavailable}
  end

  defp admission_registry, do: Runtime.name(__MODULE__.AdmissionRegistry)

  @doc "Make sure `tenant` has a running follower on this node, returning it."
  @spec follower(String.t()) :: {:ok, pid()} | {:error, term()}
  def follower(tenant) do
    case DynamicSupervisor.start_child(Runtime.name(__MODULE__.Followers), {TailFollower, {tenant, Runtime.current()}}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  @doc "Leave `tenant`'s tailers; a no-op for a process that never joined."
  @spec leave(String.t()) :: :ok
  def leave(tenant) do
    unregister_tailer(tenant)
    release(tenant)
  end

  # Either disposable registry may be unavailable during a subtree restart.
  # Clean up each independently so one missing registry cannot leak the other.
  defp unregister_tailer(tenant) do
    Registry.unregister(registry(), {:tailer, tenant})
  rescue
    ArgumentError -> :ok
  end

  defp release(tenant) do
    for {^tenant, _slot} = key <- Registry.keys(admission_registry(), self()) do
      Registry.unregister(admission_registry(), key)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  def tailers(tenant), do: for({pid, _} <- Registry.lookup(registry(), {:tailer, tenant}), do: pid)

  @doc false
  def registry, do: Runtime.name(__MODULE__.Registry)

  @doc """
  Hand records this node just acknowledged to `tenant`'s follower, if the
  tenant has tailers here; otherwise the cost is one ETS lookup.
  """
  @spec publish(String.t(), [Log.t()]) :: :ok
  def publish(_tenant, []), do: :ok

  def publish(tenant, records) do
    case Registry.lookup(Runtime.name(__MODULE__.FollowerRegistry), tenant) do
      # Request records slice the whole decoded request body; queued batches
      # must not pin those buffers beyond the bytes their credits count.
      [{pid, credit} | _] -> TailDelivery.deliver(pid, credit, :published, Pulse.JSON.detach(records))
      [] -> :ok
    end

    :ok
  rescue
    # Tail delivery is disposable. A registry restart must never turn an
    # already durable append into a failed acknowledgement and duplicate retry.
    ArgumentError -> :ok
  end

  @doc false
  def deliver(tenant, records) do
    recipients = Registry.lookup(registry(), {:tailer, tenant})

    if recipients != [] do
      bytes = :erlang.external_size(records)
      for {pid, credit} <- recipients, do: TailDelivery.deliver(pid, credit, __MODULE__, records, :close, bytes)
    end

    :ok
  end

  @doc false
  def close(tenant) do
    for {pid, credit} <- Registry.lookup(registry(), {:tailer, tenant}), do: TailDelivery.close(pid, credit)
    :ok
  end

  @doc "Compile a log query into what `select/2` needs."
  @spec compile(AST.LogQuery.t()) :: {keyword(), term()}
  def compile(%AST.LogQuery{} = query) do
    {storage_opts, stages} = Evaluator.push_down(query, %{})

    {matchers, label_regexes} =
      Enum.split_with(storage_opts[:matchers] || [], fn {_, op, _} -> op not in [:re, :nre] end)

    {lines, line_regexes} =
      Enum.split_with(storage_opts[:line_filters] || [], fn {op, _} -> op not in [:match_re, :not_match_re] end)

    regexes =
      Enum.map(label_regexes, fn {key, op, pattern} -> {key, op == :nre, compile_regex(pattern)} end) ++
        Enum.map(line_regexes, fn {op, pattern} -> {:line, op == :not_match_re, compile_regex(pattern)} end)

    opts = Keyword.take(storage_opts, [:service]) ++ [matchers: matchers, line_filters: lines, native_regexes: regexes]
    {opts, Pipeline.compile(stages)}
  end

  @doc "The pipeline entries `records` contribute to a tail, oldest first."
  @spec select({keyword(), term()}, [Log.t()]) :: [Entry.t()]
  def select({storage_opts, pipeline}, records) do
    records
    |> Memory.select_logs(storage_opts)
    |> filter_regexes(storage_opts[:native_regexes] || [])
    |> Enum.flat_map(fn record ->
      case Pipeline.apply(pipeline, Entry.from_record(record)) do
        {:keep, entry} -> [entry]
        :drop -> []
      end
    end)
    |> Enum.sort_by(&(&1.timestamp_ns || 0))
  end

  defp compile_regex(pattern) do
    {:ok, regex} = NIF.compile_log_regex(pattern)
    regex
  end

  defp matcher_value(record, :line), do: Memory.line_from_record(record)
  defp matcher_value(record, key), do: Memory.log_matcher_value(record, key)

  defp filter_regexes(records, regexes) do
    Enum.reduce(regexes, records, fn {key, negate, regex}, records ->
      rows = Enum.map(records, &{&1, matcher_value(&1, key)})
      NIF.filter_log_regex(regex, rows, negate)
    end)
  end
end
