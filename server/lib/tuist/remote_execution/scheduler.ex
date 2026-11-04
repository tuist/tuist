defmodule Tuist.RemoteExecution.Scheduler do
  @moduledoc """
  An account's execution scheduler: one process per account in the cluster,
  registered under a `:global` name and started by the first request.

  Operations, the queue and VM assignment live only in this process. Nothing
  is persisted per action: when the process is lost, so are its queued and
  running operations, and Bazel re-executes them after `WaitExecution` returns
  `NOT_FOUND` or the stream fails. Identical in-flight actions of a project
  share one operation, so those retries attach to the running execution.

  Concurrency is still bounded in PostgreSQL, per VM rather than per action
  (`Tuist.RemoteExecution.VMs`). The scheduler keeps up to `warm_pool_size`
  pristine VMs ready beyond current demand, renews its rows' leases in
  batches and destroys each VM after its single action.
  """
  use GenServer, restart: :temporary

  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.VMs
  alias Tuist.Sandboxes.Nodes

  @supervisor Tuist.RemoteExecution.Schedulers
  @tasks Tuist.RemoteExecution.Tasks
  @tick_ms 5_000
  @renew_ms 20_000
  @refresh_ms 30_000
  @retain_completed_ms 60_000
  @queue_timeout_ms 900_000
  @idle_stop_ms 600_000
  @destroy_retry_ms 10_000
  @prepare_backoff_ms 5_000
  # Demand sizing for the warm pool: observed preparation time is the lead
  # time, and a build's peak outlives the gap between builds.
  @warm_hold_ms 60_000
  @initial_prepare_ms 50
  # A VM is assigned only while its last renewal leaves most of the lease.
  @fresh_lease_ms 40_000
  # A cached project credential must outlive the longest action it is given to.
  @token_min_remaining_seconds 780
  # The gateway stops using a lease this long before its node expires it.
  @lease_margin_ms 5_000

  def name(account_id), do: {:global, {__MODULE__, account_id}}

  def whereis(account_id) do
    case :global.whereis_name({__MODULE__, account_id}) do
      :undefined -> nil
      pid -> pid
    end
  end

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :account_id)}, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: name(Keyword.fetch!(opts, :account_id)))
  end

  def submit(account_id, attrs, wait_ms) do
    with {:ok, pid} <- ensure_started(account_id) do
      call(pid, {:submit, attrs, wait_ms}, wait_ms)
    end
  end

  def lease(account_id, attrs, wait_ms) do
    with {:ok, pid} <- ensure_started(account_id) do
      call(pid, {:lease, attrs, wait_ms}, wait_ms)
    end
  end

  def await(account_id, project_id, id, after_state, wait_ms) do
    case whereis(account_id) do
      nil -> {:error, :not_found}
      pid -> call(pid, {:await, project_id, id, after_state, wait_ms}, wait_ms)
    end
  end

  def reload(account_id) do
    case whereis(account_id) do
      nil -> :ok
      pid -> send(pid, :refresh)
    end

    :ok
  end

  defp ensure_started(account_id) do
    case whereis(account_id) do
      nil ->
        case DynamicSupervisor.start_child(@supervisor, {__MODULE__, account_id: account_id}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          _ -> {:error, :unavailable}
        end

      pid ->
        {:ok, pid}
    end
  end

  # A scheduler that stops mid-call loses its operations by design. The caller
  # reports the operation as unknown, which Bazel answers by executing again.
  defp call(pid, message, wait_ms) do
    GenServer.call(pid, message, wait_ms + 5_000)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @impl GenServer
  def init(opts) do
    account_id = Keyword.fetch!(opts, :account_id)

    case RemoteExecution.available_settings(account_id) do
      {:ok, settings} ->
        Process.flag(:trap_exit, true)
        Process.send_after(self(), :tick, @tick_ms)
        Process.send_after(self(), :renew, @renew_ms)
        Process.send_after(self(), :refresh, @refresh_ms)

        {:ok,
         %{
           account_id: account_id,
           settings: settings,
           ops: %{},
           queue: :queue.new(),
           lease_waiters: :queue.new(),
           inflight: %{},
           vms: %{},
           tasks: %{},
           tokens: %{},
           blocked_on: nil,
           prepare_after: now_ms(),
           active_at: now_ms(),
           arrivals: :queue.new(),
           prepare_ms: @initial_prepare_ms,
           warm_peak: 0,
           warm_peak_at: now_ms()
         }, {:continue, :reconcile}}

      _ ->
        :ignore
    end
  end

  @impl GenServer
  def handle_continue(:reconcile, state), do: {:noreply, reconcile(state)}

  @impl GenServer
  def handle_call({:submit, _attrs, _wait_ms}, _from, %{settings: nil} = state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call({:lease, _attrs, _wait_ms}, _from, %{settings: nil} = state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call({:submit, attrs, wait_ms}, from, state) do
    state = %{state | active_at: now_ms()}
    key = {attrs.project_id, attrs.hash, attrs.size}

    case not attrs.skip_cache and Map.get(state.inflight, key) do
      id when is_binary(id) ->
        submitted("deduplicated")
        wait_for(state, id, from, :done, wait_ms)

      _ ->
        if :queue.len(state.queue) >= queue_limit(state.settings) do
          submitted("queue_full")
          {:reply, {:error, :queue_full}, state}
        else
          submitted("accepted")
          op = new_operation(attrs, state.settings, :queue.len(state.queue))
          inflight = if attrs.skip_cache, do: state.inflight, else: Map.put(state.inflight, key, op.id)

          state =
            dispatch(%{
              state
              | ops: Map.put(state.ops, op.id, op),
                queue: :queue.in(op.id, state.queue),
                inflight: inflight,
                arrivals: :queue.in(state.active_at, state.arrivals)
            })

          wait_for(state, op.id, from, :done, wait_ms)
        end
    end
  end

  def handle_call({:lease, attrs, wait_ms}, from, state) do
    timer = make_ref()
    Process.send_after(self(), {:lease_timeout, timer}, wait_ms)
    waiter = %{from: from, attrs: attrs, timer: timer}
    {:noreply, dispatch(%{state | active_at: now_ms(), lease_waiters: :queue.in(waiter, state.lease_waiters)})}
  end

  def handle_call({:await, project_id, id, after_state, wait_ms}, from, state) do
    state = %{state | active_at: now_ms()}

    case Map.get(state.ops, id) do
      %{project_id: ^project_id} when is_binary(after_state) ->
        wait_for(state, id, from, {:change, after_state}, wait_ms)

      %{project_id: ^project_id} ->
        wait_for(state, id, from, :done, 0)

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.pop(state.tasks, ref) do
      {nil, _tasks} ->
        {:noreply, state}

      {task, tasks} ->
        Process.demonitor(ref, [:flush])
        {:noreply, handle_task(task, result, %{state | tasks: tasks})}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.tasks, ref) do
      {nil, _tasks} -> {:noreply, state}
      {task, tasks} -> {:noreply, handle_task(task, :crashed, %{state | tasks: tasks})}
    end
  end

  def handle_info({:waiter_timeout, id, timer}, state) do
    case Map.get(state.ops, id) do
      nil ->
        {:noreply, state}

      op ->
        {expired, waiting} = Enum.split_with(op.waiters, fn {_from, _mode, waiter} -> waiter == timer end)
        Enum.each(expired, fn {from, _mode, _timer} -> GenServer.reply(from, {:ok, view(op)}) end)
        {:noreply, put_op(state, %{op | waiters: waiting})}
    end
  end

  def handle_info({:lease_timeout, timer}, state) do
    {expired, waiting} = state.lease_waiters |> :queue.to_list() |> Enum.split_with(&(&1.timer == timer))

    Enum.each(expired, fn waiter ->
      GenServer.reply(waiter.from, {:ok, nil})
      leased("timeout")
    end)

    {:noreply, %{state | lease_waiters: :queue.from_list(waiting)}}
  end

  def handle_info({:destroy, vm_id}, state) do
    case Map.get(state.vms, vm_id) do
      %{state: :retiring} = vm -> {:noreply, start_destroy(state, vm, nil)}
      _ -> {:noreply, state}
    end
  end

  def handle_info(:renew, state) do
    Process.send_after(self(), :renew, @renew_ms)
    ids = for {id, %{sandbox: %{}}} <- state.vms, do: id
    sent_at = now_ms()
    {:noreply, start_task(state, {:renew, ids, sent_at}, fn -> VMs.renew(ids) end)}
  end

  def handle_info(:refresh, state) do
    case RemoteExecution.available_settings(state.account_id) do
      {:ok, settings} ->
        Process.send_after(self(), :refresh, @refresh_ms)
        {:noreply, reconcile(%{state | settings: settings})}

      _ ->
        Process.send_after(self(), :refresh, @refresh_ms)
        state = fail_queued(%{state | settings: nil}, 9, "execution disabled")
        {:noreply, reconcile(state)}
    end
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    now = now_ms()

    expired = for {id, %{state: :queued, queued_mono: at}} <- state.ops, now - at > @queue_timeout_ms, do: id
    state = Enum.reduce(expired, state, &complete(&2, &1, {:error, 14, "execution queue timed out"}))

    ops =
      Map.reject(state.ops, fn {_id, op} ->
        op.state == :completed and op.waiters == [] and now - op.completed_mono > @retain_completed_ms
      end)

    state = reconcile(%{state | ops: ops, blocked_on: nil})

    if idle?(state, now), do: {:stop, :normal, state}, else: {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Stopping hands the VMs to the minute reaper instead of waiting out their
  # leases. Running actions end with this process; Bazel retries them.
  @impl GenServer
  def terminate(_reason, state) do
    VMs.expire(for {id, %{sandbox: %{}}} <- state.vms, do: id)
  end

  # Prefetched inputs are kept only while a VM is likely to free up soon, which
  # bounds what a long queue holds in memory. Later actions fetch their own.
  defp new_operation(attrs, settings, queued) do
    attrs = if queued >= settings.max_concurrency, do: %{attrs | inputs: nil}, else: attrs

    Map.merge(attrs, %{
      id: Ecto.UUID.generate(),
      state: :queued,
      queued_at_unix_us: System.system_time(:microsecond),
      queued_mono: now_ms(),
      dispatched_mono: nil,
      completed_mono: nil,
      cas_endpoint: settings.cas_endpoint,
      waiters: [],
      vm: nil,
      response: nil,
      cacheable: false,
      code: 0,
      message: nil
    })
  end

  defp wait_for(state, id, from, mode, wait_ms) do
    op = Map.fetch!(state.ops, id)

    if wait_ms <= 0 or satisfied?(op, mode) do
      {:reply, {:ok, view(op)}, state}
    else
      timer = make_ref()
      Process.send_after(self(), {:waiter_timeout, id, timer}, wait_ms)
      {:noreply, put_op(state, %{op | waiters: [{from, mode, timer} | op.waiters]})}
    end
  end

  defp satisfied?(%{state: :completed}, _mode), do: true
  defp satisfied?(op, {:change, after_state}), do: Atom.to_string(op.state) != after_state
  defp satisfied?(_op, :done), do: false

  defp notify(state, id) do
    op = Map.fetch!(state.ops, id)
    {ready, waiting} = Enum.split_with(op.waiters, fn {_from, mode, _timer} -> satisfied?(op, mode) end)
    Enum.each(ready, fn {from, _mode, _timer} -> GenServer.reply(from, {:ok, view(op)}) end)
    put_op(state, %{op | waiters: waiting})
  end

  defp view(op) do
    base = %{
      id: op.id,
      state: Atom.to_string(op.state),
      done: op.state == :completed,
      queued_at_unix_us: op.queued_at_unix_us,
      response: op.response,
      code: op.code,
      message: op.message
    }

    if op.cacheable,
      do: Map.merge(base, %{cacheable: true, action_hash: op.hash, action_size: op.size, cas_endpoint: op.cas_endpoint}),
      else: base
  end

  defp dispatch(state) do
    case :queue.peek(state.queue) do
      :empty ->
        grant_leases(state)

      {:value, id} ->
        case {Map.get(state.ops, id), ready_vm(state)} do
          {%{state: :queued}, nil} -> reconcile(state)
          {%{state: :queued} = op, vm} -> dispatch(start_run(%{state | queue: :queue.drop(state.queue)}, op, vm))
          # Completed while queued (timed out or disabled).
          _ -> dispatch(%{state | queue: :queue.drop(state.queue)})
        end
    end
  end

  defp ready_vm(state) do
    now = now_ms()

    state.vms
    |> Map.values()
    |> Enum.filter(&(&1.state == :ready and now - &1.renewed_at < @fresh_lease_ms))
    |> Enum.min_by(& &1.renewed_at, fn -> nil end)
  end

  defp start_run(state, op, vm) do
    request = %{
      endpoint: op.cas_endpoint,
      account: op.account_name,
      instance: op.project_name,
      hash: op.hash,
      size: op.size,
      image: vm.sandbox.template_tag
    }

    request = if op.inputs, do: Map.put(request, :inputs, op.inputs), else: request

    token = cached_token(state, op.project_id)

    state
    |> put_op(%{op | state: :executing, vm: vm.id, inputs: nil, dispatched_mono: now_ms()})
    |> put_vm(%{vm | state: :busy})
    |> start_task({:run, op.id, vm.id}, fn -> VMs.execute(vm.sandbox, request, op.project_id, token) end)
    |> notify(op.id)
  end

  # Queued operations take ready VMs first; leases get the rest.
  defp grant_leases(state) do
    with {:value, waiter} <- :queue.peek(state.lease_waiters),
         %{} = vm <- ready_vm(state) do
      grant_leases(grant(%{state | lease_waiters: :queue.drop(state.lease_waiters)}, waiter, vm))
    else
      _ -> reconcile(state)
    end
  end

  defp grant(state, waiter, vm) do
    case direct_endpoint(vm.sandbox.node_name) do
      nil ->
        GenServer.reply(waiter.from, {:error, :unsupported})
        leased("unsupported")
        state

      endpoint ->
        nonce = :crypto.strong_rand_bytes(32)
        digest = Base.encode16(:crypto.hash(:sha256, nonce), case: :lower)
        project_id = waiter.attrs.project_id
        token = cached_token(state, project_id)

        GenServer.reply(
          waiter.from,
          {:ok,
           %{
             sandbox_id: vm.sandbox.id,
             endpoint: endpoint,
             nonce: Base.encode64(nonce),
             image: vm.sandbox.template_tag,
             cas_endpoint: state.settings.cas_endpoint,
             expires_in_ms: VMs.claim_timeout_ms() - @lease_margin_ms
           }}
        )

        %{state | arrivals: :queue.in(now_ms(), state.arrivals)}
        |> put_vm(%{vm | state: :leased})
        |> start_task({:lease, vm.id, project_id}, fn -> VMs.lease(vm.sandbox, digest, project_id, token) end)
    end
  end

  defp direct_endpoint(node) do
    case Nodes.lookup(node) do
      {:ok, _pid, %{direct_exec_endpoint: "http" <> _ = endpoint}} -> endpoint
      _ -> nil
    end
  end

  defp cached_token(state, project_id) do
    case Map.get(state.tokens, project_id) do
      {token, expires_at} -> if expires_at - System.system_time(:second) >= @token_min_remaining_seconds, do: token
      nil -> nil
    end
  end

  defp handle_task({:run, op_id, vm_id}, result, state) do
    {result, state} =
      case result do
        {result, {token, expires_at}} ->
          {result, put_in(state.tokens[Map.fetch!(state.ops, op_id).project_id], {token, expires_at})}

        {result, nil} ->
          {result, state}

        :crashed ->
          {{:error, 14, "execution worker failed"}, state}
      end

    state
    |> complete(op_id, result)
    |> retire(vm_id, nil)
    |> dispatch()
  end

  defp handle_task({:lease, vm_id, project_id}, result, state) do
    {result, state} =
      case result do
        {result, {token, expires_at}} -> {result, put_in(state.tokens[project_id], {token, expires_at})}
        {result, nil} -> {result, state}
        :crashed -> {:crashed, state}
      end

    leased(
      case result do
        :claimed -> "claimed"
        :unclaimed -> "unclaimed"
        _ -> "failed"
      end
    )

    case {result, Map.get(state.vms, vm_id)} do
      {:unclaimed, %{state: :leased} = vm} -> dispatch(put_vm(state, %{vm | state: :ready}))
      _ -> state |> retire(vm_id, nil) |> dispatch()
    end
  end

  defp handle_task({:prepare, placeholder}, result, state) do
    started_at = state.vms |> Map.fetch!(placeholder) |> Map.fetch!(:renewed_at)
    state = %{state | vms: Map.delete(state.vms, placeholder)}
    prepared(result, now_ms() - started_at)

    case result do
      {:ok, sandbox} ->
        prepare_ms = round(0.8 * state.prepare_ms + 0.2 * (now_ms() - started_at))

        dispatch(
          put_vm(%{state | prepare_ms: prepare_ms}, %{
            id: sandbox.id,
            sandbox: sandbox,
            state: :ready,
            renewed_at: now_ms()
          })
        )

      # No node had room. Nothing was created, so this waits for one of the
      # account's placed VMs to free a node, or for the next tick.
      {:error, sandbox, nil} ->
        %{state | blocked_on: :node}
        |> put_vm(%{id: sandbox.id, sandbox: sandbox, state: :retiring, renewed_at: now_ms()})
        |> retire(sandbox.id, nil)

      # Unavailable nodes must not turn into a create/delete loop.
      {:error, sandbox, not_before} ->
        %{state | prepare_after: now_ms() + @prepare_backoff_ms}
        |> put_vm(%{id: sandbox.id, sandbox: sandbox, state: :retiring, renewed_at: now_ms()})
        |> retire(sandbox.id, not_before)

      # At the cap: other VMs of the account are still being deleted.
      :busy ->
        %{state | blocked_on: :cap}

      _ ->
        state
    end
  end

  # Any deletion frees an account slot; only a placed VM's frees node room.
  defp handle_task({:destroy, vm_id}, :ok, state) do
    placed = match?(%{sandbox: %{node_name: node}} when is_binary(node), Map.get(state.vms, vm_id))
    blocked_on = if state.blocked_on == :node and not placed, do: :node
    reconcile(%{state | vms: Map.delete(state.vms, vm_id), blocked_on: blocked_on})
  end

  defp handle_task({:destroy, vm_id}, _error, state) do
    Process.send_after(self(), {:destroy, vm_id}, @destroy_retry_ms)
    state
  end

  defp handle_task({:renew, ids, sent_at}, renewed, state) when is_list(renewed) do
    renewed = MapSet.new(renewed)

    vms =
      Enum.reduce(ids, state.vms, fn id, vms ->
        case Map.get(vms, id) do
          nil -> vms
          vm -> if MapSet.member?(renewed, id), do: Map.put(vms, id, %{vm | renewed_at: sent_at}), else: lost(vms, vm)
        end
      end)

    reconcile(%{state | vms: vms})
  end

  defp handle_task({:renew, _ids, _sent_at}, _error, state), do: state

  # The reaper deleted this row: its VM is gone or being deleted. A busy or
  # leased VM's action fails on its own; idle and retiring ones need nothing more.
  defp lost(vms, %{state: state}) when state in [:busy, :leased], do: vms
  defp lost(vms, vm), do: Map.delete(vms, vm.id)

  defp complete(state, id, result) do
    op = Map.fetch!(state.ops, id)

    op =
      case result do
        {:ok, response, cacheable} -> %{op | response: response, cacheable: cacheable}
        {:error, code, message} -> %{op | code: code, message: message}
      end

    now = now_ms()

    :telemetry.execute(
      [:tuist, :remote_execution, :operation],
      %{duration: now - op.queued_mono, queue_time: (op.dispatched_mono || now) - op.queued_mono},
      %{outcome: outcome(op.code)}
    )

    key = {op.project_id, op.hash, op.size}
    inflight = if Map.get(state.inflight, key) == id, do: Map.delete(state.inflight, key), else: state.inflight

    %{state | inflight: inflight}
    |> put_op(%{op | state: :completed, vm: nil, completed_mono: now})
    |> notify(id)
  end

  defp fail_queued(state, code, message) do
    queued = for {id, %{state: :queued}} <- state.ops, do: id
    Enum.reduce(queued, state, &complete(&2, &1, {:error, code, message}))
  end

  defp retire(state, vm_id, not_before) do
    case Map.get(state.vms, vm_id) do
      nil -> state
      vm -> start_destroy(put_vm(state, %{vm | state: :retiring}), vm, not_before)
    end
  end

  defp start_destroy(state, vm, not_before) do
    start_task(state, {:destroy, vm.id}, fn -> VMs.destroy(vm.sandbox, not_before) end)
  end

  # Keeps the VMs that queued work and the warm target need, within the cap.
  # Retiring VMs still hold capacity until their deletion is acknowledged.
  defp reconcile(%{settings: nil} = state) do
    state.vms
    |> Map.values()
    |> Enum.filter(&(&1.state == :ready))
    |> Enum.reduce(state, &retire(&2, &1.id, nil))
  end

  defp reconcile(state) do
    settings = state.settings
    {warm, state} = warm_target(state, now_ms())
    queued = Enum.count(state.ops, fn {_id, op} -> op.state == :queued end) + :queue.len(state.lease_waiters)
    ready = state.vms |> Map.values() |> Enum.filter(&(&1.state == :ready))
    {stale, ready} = Enum.split_with(ready, &(not matches?(&1.sandbox, settings)))
    excess = if queued == 0, do: Enum.drop(Enum.sort_by(ready, & &1.renewed_at, :desc), warm), else: []
    state = Enum.reduce(stale ++ excess, state, &retire(&2, &1.id, nil))

    vms = Map.values(state.vms)
    count = fn states -> Enum.count(vms, &(&1.state in states)) end
    desired = min(settings.max_concurrency, count.([:busy, :leased]) + queued + warm)
    room = min(desired - count.([:reserving, :ready, :busy, :leased]), settings.max_concurrency - map_size(state.vms))

    if room > 0 and is_nil(state.blocked_on) and now_ms() >= state.prepare_after do
      Enum.reduce(1..room, state, fn _, state -> start_prepare(state) end)
    else
      state
    end
  end

  # Ready VMs for each action to find one: the actions that arrived within one
  # preparation time, which is how many VMs are consumed while a replacement is
  # prepared (Little's law), plus one. A build's peak is held across the gap
  # before the next build, then falls back to the current demand.
  # `warm_pool_size` caps it as the hosts' budget.
  defp warm_target(state, now) do
    arrivals = drop_old_arrivals(state.arrivals, now - state.prepare_ms)
    count = :queue.len(arrivals)
    demand = if count > 0, do: count + 1, else: 0

    {peak, peak_at} =
      if demand >= state.warm_peak or now - state.warm_peak_at > @warm_hold_ms,
        do: {demand, now},
        else: {state.warm_peak, state.warm_peak_at}

    {min(peak, state.settings.warm_pool_size), %{state | arrivals: arrivals, warm_peak: peak, warm_peak_at: peak_at}}
  end

  defp drop_old_arrivals(arrivals, since) do
    case :queue.peek(arrivals) do
      {:value, at} when at < since -> drop_old_arrivals(:queue.drop(arrivals), since)
      _ -> arrivals
    end
  end

  defp matches?(sandbox, settings),
    do: sandbox.template_tag == settings.image_tag and sandbox.node_name in settings.node_names

  defp start_prepare(state) do
    placeholder = make_ref()
    settings = state.settings
    account_id = state.account_id

    state
    |> put_vm(%{id: placeholder, sandbox: nil, state: :reserving, renewed_at: now_ms()})
    |> start_task({:prepare, placeholder}, fn ->
      case VMs.reserve(account_id, settings) do
        {:ok, sandbox} -> VMs.prepare(sandbox, settings)
        {:error, :busy} -> :busy
      end
    end)
  end

  defp start_task(state, key, fun) do
    task = Task.Supervisor.async_nolink(@tasks, fun)
    %{state | tasks: Map.put(state.tasks, task.ref, key)}
  end

  defp idle?(state, now) do
    state.ops == %{} and state.vms == %{} and state.tasks == %{} and now - state.active_at > @idle_stop_ms
  end

  # Telemetry carries no account or project: the outcome sets are fixed.
  defp submitted(outcome),
    do: :telemetry.execute([:tuist, :remote_execution, :submission], %{count: 1}, %{outcome: outcome})

  defp leased(outcome), do: :telemetry.execute([:tuist, :remote_execution, :lease], %{count: 1}, %{outcome: outcome})

  defp prepared(result, duration) do
    outcome =
      case result do
        {:ok, _sandbox} -> "ok"
        {:error, _sandbox, nil} -> "no_node"
        {:error, _sandbox, _not_before} -> "unavailable"
        :busy -> "at_capacity"
        _ -> "failed"
      end

    :telemetry.execute([:tuist, :remote_execution, :prepare], %{duration: duration}, %{outcome: outcome})
  end

  defp outcome(0), do: "ok"
  defp outcome(9), do: "failed_precondition"
  defp outcome(13), do: "internal"
  defp outcome(14), do: "unavailable"
  defp outcome(_code), do: "other"

  defp queue_limit(settings), do: min(settings.max_concurrency * 4, 512)
  defp put_op(state, op), do: %{state | ops: Map.put(state.ops, op.id, op)}
  defp put_vm(state, vm), do: %{state | vms: Map.put(state.vms, vm.id, vm)}
  defp now_ms, do: System.monotonic_time(:millisecond)
end
