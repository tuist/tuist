defmodule Tuist.Authentication.SingleFlight do
  @moduledoc """
  Direct ETS cache reads with atomic per-key fill claims. Each cold key has its
  own short-lived coordinator and monitored fill worker, not a shared mailbox.
  The GenServer only owns the claims table; requests never call or message it.
  Fills capture the data-table ID, so a name-based restart cannot redirect an
  old write into a new generation, even between the publication check and write.
  Publication checks the claim and remaining budget independently of coordinator
  progress. Timeout cancellation still discards unfinished work; no late-fill
  retention policy is implied. A same-generation write can straddle the final
  deadline check; immutable proofs remain valid and subject snapshots still
  enforce their original deadline on every hit.
  """
  use GenServer

  import Cachex.Spec, only: [cache: 2]

  alias Cachex.Services.Overseer

  @timeout to_timeout(second: 30)

  def cache_child_spec(id, cache, options) do
    children = [{Cachex, [cache, options]}, {__MODULE__, cache}]
    %{id: id, type: :supervisor, start: {Supervisor, :start_link, [children, [strategy: :one_for_all]]}}
  end

  def start_link(cache), do: GenServer.start_link(__MODULE__, cache)

  @impl true
  def init(cache) do
    table = String.to_atom("#{cache}_flights")
    :ets.new(table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: :auto])
    {:ok, table}
  end

  def fetch(cache, key, fallback, opts \\ []) do
    case Cachex.get(cache, key, nil, notify: false) do
      nil ->
        table = cache |> table_name() |> :ets.whereis()

        context = %{
          cache: cache,
          data: cache(Overseer.lookup(cache), name: :ets.whereis(cache)),
          key: key,
          table: table,
          fallback: fallback,
          deadline: :erlang.monotonic_time(:millisecond) + Keyword.get(opts, :timeout, @timeout),
          retries: 2,
          initiator: false
        }

        elect(context)

      {:error, _} ->
        {:error, :unavailable}

      value ->
        value
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  defp table_name(cache), do: String.to_existing_atom("#{cache}_flights")

  defp elect(context) do
    if remaining(context) == 0 do
      {:error, :unavailable}
    else
      case :ets.lookup(context.table, context.key) do
        [{_, pid}] -> await(pid, Process.monitor(pid), context)
        [] -> claim(context)
      end
    end
  end

  defp claim(context) do
    owner = :ets.info(context.table, :owner)
    caller = self()
    callers = Process.get(:"$callers", [])
    {pid, ref} = spawn_monitor(fn -> candidate(context, owner, caller, callers) end)

    try do
      if :ets.insert_new(context.table, {context.key, pid}) do
        send(pid, {:execute, caller})
        await(pid, ref, %{context | initiator: true})
      else
        discard(pid, ref)
        retry(context)
      end
    rescue
      ArgumentError ->
        discard(pid, ref)
        {:error, :unavailable}
    end
  end

  defp candidate(context, owner, caller, callers) do
    Process.put(:"$callers", [caller | callers])
    owner_ref = Process.monitor(owner)
    caller_ref = Process.monitor(caller)

    result =
      receive do
        {:execute, ^caller} ->
          Process.demonitor(caller_ref, [:flush])
          run(owner_ref, Map.put(context, :flight, self()))

        {:DOWN, _, :process, _, _} ->
          {:error, :unavailable}
      after
        remaining(context) -> {:error, :unavailable}
      end

    release(context, self())
    exit({:single_flight_result, result})
  end

  defp run(owner_ref, context) do
    Process.flag(:trap_exit, true)
    parent = self()
    callers = Process.get(:"$callers", [])

    worker =
      spawn_link(fn ->
        Process.put(:"$callers", [parent | callers])
        send(parent, {:completed, self(), fill(context)})
      end)

    receive do
      {:completed, ^worker, result} -> result
      {:EXIT, ^worker, _} -> {:error, :unavailable}
      {:DOWN, ^owner_ref, :process, _, _} -> cancel(context, worker)
    after
      remaining(context) -> cancel(context, worker)
    end
  end

  defp fill(context) do
    case Cachex.get(context.data, context.key, nil, notify: false) do
      nil -> persist(context, context.fallback.())
      {:error, _} -> {:error, :unavailable}
      value -> value
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp persist(context, {:commit, value}), do: persist(context, {:commit, value, []})

  defp persist(context, {:commit, value, options}) do
    with true <- publishable?(context),
         :ok <- Cachex.put(context.data, context.key, value, [notify: false] ++ options) do
      {:commit, value}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp persist(context, {:ignore, value}) do
    if publishable?(context), do: {:ignore, value}, else: {:error, :unavailable}
  end

  defp persist(_context, _error), do: {:error, :unavailable}

  defp publishable?(context) do
    remaining(context) > 0 and
      :ets.whereis(table_name(context.cache)) == context.table and
      :ets.lookup(context.table, context.key) == [{context.key, context.flight}]
  end

  defp await(pid, ref, context) do
    receive do
      {:DOWN, ^ref, :process, ^pid, {:single_flight_result, result}} ->
        release(context, pid)
        completed(result, context)

      {:DOWN, ^ref, :process, ^pid, :noproc} ->
        release(context, pid)
        retry(context)

      {:DOWN, ^ref, :process, ^pid, _} ->
        release(context, pid)
        completed({:error, :unavailable}, context)
    after
      remaining(context) ->
        if context.initiator do
          release(context, pid)
          Process.exit(pid, :kill)
        end

        Process.demonitor(ref, [:flush])
        {:error, :unavailable}
    end
  end

  defp completed({:error, :unavailable}, %{initiator: true}), do: {:error, :unavailable}
  defp completed({:error, :unavailable}, context), do: retry(context)
  defp completed(result, _context), do: result

  defp retry(%{retries: 0}), do: {:error, :unavailable}

  defp retry(context) do
    context = %{context | retries: context.retries - 1}

    case Cachex.get(context.data, context.key, nil, notify: false) do
      nil -> elect(context)
      {:error, _} -> {:error, :unavailable}
      value -> value
    end
  end

  defp discard(pid, ref) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
  end

  defp remaining(context), do: max(context.deadline - :erlang.monotonic_time(:millisecond), 0)

  defp cancel(context, worker) do
    release(context, self())
    Process.exit(worker, :kill)
    {:error, :unavailable}
  end

  defp release(context, pid) do
    :ets.delete_object(context.table, {context.key, pid})
  rescue
    ArgumentError -> :ok
  end
end
