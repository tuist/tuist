defmodule Condukt.Sandbox.Services do
  @moduledoc """
  Long-lived processes in a sandbox, such as a dev server or a database,
  that belong to a session rather than a turn: aborting a turn or a tool
  call leaves them alone, and they run until the services process stops.

  Each service is a sandbox process (`c:Condukt.Sandbox.start_process/4`)
  named `condukt-service:<owner>:<name>`, outside the ids `Condukt.Tools.Bash`
  uses, so nothing a turn does reaches it. The services process starts them,
  checks their readiness, restarts one that exits, and exposes its port when
  the sandbox implements `c:Condukt.Sandbox.expose_port/3`.

      {:ok, services} =
        Condukt.Sandbox.Services.start_link(sandbox,
          owner: session_id,
          services: [
            %{name: "web", command: "bin/dev", port: 4000, ready: {:port, 4000}},
            %{name: "db", command: "postgres -D tmp/db", ready: {:command, "pg_isready"}}
          ]
        )

      Condukt.Sandbox.Services.list(services)
      #=> [%{name: "web", status: :ready, url: "https://…", restarts: 0}, …]

  A service map takes `:name`, `:command`, and optionally `:cwd`, `:env`,
  `:port` (exposed once ready), `:ready` (`{:port, port}`, checked with
  bash's `/dev/tcp`, or `{:command, shell}`, which must exit 0; without it a
  running service is ready), and `:restart` (`:always`, the default,
  `:on_failure`, or `:never`). Restarts back off from one second to a minute,
  and the backoff starts over once a service has stayed ready for 30 seconds,
  so one that crashes soon after it is ready keeps backing off. A failed
  status read leaves a service alone until the next check; only a process the
  sandbox no longer has counts as exited.

  Subscribers get `{Condukt.Sandbox.Services, name, status}` whenever a
  service's status changes. Pass `subscribers: [pid]` to `start_link/2` to
  hear the first changes, which may come before a later `subscribe/1`. A host shows `list/1` beside the session's view;
  the session itself does not hold services.

  Environment and secrets are given once, at start. `restart/2` with `:env`
  starts a service again with new ones, as refreshing credentials needs.
  """

  use GenServer

  alias Condukt.Sandbox

  @check_every 1_000
  @min_backoff 1_000
  @max_backoff 60_000
  # How long a service stays ready before its backoff starts over.
  @stable_after 30_000

  def start_link(%Sandbox{} = sandbox, opts), do: GenServer.start_link(__MODULE__, {sandbox, opts})

  @doc "Each service's name, `status` (`:starting | :ready | :exited | :failed`), `url`, and `restarts`."
  def list(services), do: GenServer.call(services, :list)

  @doc "Subscribes the caller to status changes."
  def subscribe(services), do: GenServer.call(services, {:subscribe, self()})

  @doc "Starts a service again, with `:env` replacing its environment when given."
  def restart(services, name, opts \\ []), do: GenServer.call(services, {:restart, name, opts}, 60_000)

  @doc "The sandbox process id of a service."
  def process_id(owner, name), do: "condukt-service:#{owner}:#{name}"

  @impl true
  def init({sandbox, opts}) do
    owner = Keyword.fetch!(opts, :owner)

    services =
      Map.new(Keyword.get(opts, :services, []), fn spec ->
        spec = Map.new(spec)
        name = Map.fetch!(spec, :name)

        {name,
         %{
           spec: spec,
           id: process_id(owner, name),
           status: :starting,
           url: nil,
           restarts: 0,
           backoff: @min_backoff,
           retry_at: nil,
           ready_at: nil,
           start: 0
         }}
      end)

    Process.flag(:trap_exit, true)
    subscribers = Map.new(Keyword.get(opts, :subscribers, []), &{&1, Process.monitor(&1)})
    state = %{sandbox: sandbox, services: services, subscribers: subscribers, checking: nil}
    send(self(), :check)
    {:ok, Enum.reduce(Map.keys(services), state, &start_service(&2, &1))}
  end

  @impl true
  def handle_call(:list, _from, state) do
    list =
      state.services
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {name, s} -> %{name: name, status: s.status, url: s.url, restarts: s.restarts} end)

    {:reply, list, state}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, Process.monitor(pid))}}
  end

  def handle_call({:restart, name, opts}, _from, state) do
    case state.services do
      %{^name => service} ->
        _ = Sandbox.stop_process(state.sandbox, service.id)
        spec = if opts[:env], do: Map.put(service.spec, :env, opts[:env]), else: service.spec
        state = put_in(state.services[name], %{service | spec: spec, backoff: @min_backoff, retry_at: nil})
        {:reply, :ok, start_service(state, name)}

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info(:check, state) do
    Process.send_after(self(), :check, @check_every)
    state = Enum.reduce(Map.keys(state.services), state, &restart_due(&2, &1))
    {:noreply, if(state.checking, do: state, else: start_check(state))}
  end

  def handle_info({ref, observations}, %{checking: ref} = state) do
    Process.demonitor(ref, [:flush])

    state =
      Enum.reduce(observations, %{state | checking: nil}, fn {name, start, observed}, state ->
        service = state.services[name]
        if service.start == start and service.retry_at == nil, do: observe(state, name, observed), else: state
      end)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{checking: ref} = state),
    do: {:noreply, %{state | checking: nil}}

  def handle_info({:DOWN, monitor, :process, pid, _reason}, state) do
    case state.subscribers do
      %{^pid => ^monitor} -> {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
      _ -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    for {_name, service} <- state.services, do: Sandbox.stop_process(state.sandbox, service.id)
    :ok
  end

  defp start_service(state, name) do
    service = %{state.services[name] | start: state.services[name].start + 1}
    state = put_in(state.services[name], service)
    _ = Sandbox.stop_process(state.sandbox, service.id)
    opts = [cwd: service.spec[:cwd], env: service.spec[:env] || []]

    case Sandbox.start_process(state.sandbox, service.id, service.spec.command, opts) do
      result when result in [:ok, {:error, :already_started}] -> set_status(state, name, :starting)
      {:error, _reason} -> retry_later(state, name, :failed)
    end
  end

  defp restart_due(state, name) do
    service = state.services[name]

    if service.retry_at && System.monotonic_time(:millisecond) >= service.retry_at do
      state = put_in(state.services[name].restarts, service.restarts + 1)
      start_service(put_in(state.services[name].retry_at, nil), name)
    else
      state
    end
  end

  # Status reads and readiness probes run in a task, so a slow probe never
  # holds up `list/1` or a restart. What a task saw applies only to the start
  # of the service it saw, not to one a restart began meanwhile.
  defp start_check(state) do
    sandbox = state.sandbox
    targets = for {name, service} <- state.services, service.retry_at == nil, do: {name, service}

    task =
      Task.async(fn ->
        Enum.map(targets, fn {name, service} -> {name, service.start, observation(sandbox, service)} end)
      end)

    %{state | checking: task.ref}
  end

  defp observation(sandbox, service) do
    case Sandbox.read_process(sandbox, service.id, 0, max_bytes: 0) do
      {:ok, %{status: :running}} -> {:running, ready?(sandbox, service)}
      {:ok, %{status: status}} -> {:exited, status}
      {:error, :not_found} -> {:exited, {:exited, nil}}
      # The sandbox could not be read, as while its node restarts; the
      # service may well be running.
      {:error, _reason} -> :unknown
    end
  end

  defp observe(state, name, {:running, true}), do: ready(state, name)
  defp observe(state, name, {:exited, status}), do: exited(state, name, status)
  defp observe(state, _name, _running_or_unknown), do: state

  defp ready?(_sandbox, %{status: :ready}), do: true
  defp ready?(_sandbox, %{spec: %{ready: nil}}), do: true
  defp ready?(_sandbox, %{spec: spec}) when not is_map_key(spec, :ready), do: true

  defp ready?(sandbox, %{spec: %{ready: {:port, port}}}), do: probe(sandbox, "exec 3<>/dev/tcp/127.0.0.1/#{port}")

  defp ready?(sandbox, %{spec: %{ready: {:command, command}}}), do: probe(sandbox, command)

  defp probe(sandbox, command), do: match?({:ok, %{exit_code: 0}}, Sandbox.exec(sandbox, command, timeout: 5_000))

  defp ready(%{services: services} = state, name) do
    service = services[name]

    now = System.monotonic_time(:millisecond)

    cond do
      service.status != :ready ->
        url = expose(state, service.spec[:port])
        state = put_in(state.services[name], %{service | url: url, ready_at: now})
        set_status(state, name, :ready)

      service.backoff != @min_backoff and now - service.ready_at >= @stable_after ->
        put_in(state.services[name].backoff, @min_backoff)

      true ->
        state
    end
  end

  defp expose(_state, nil), do: nil

  defp expose(state, port) do
    case Sandbox.expose_port(state.sandbox, port) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp exited(state, name, status) do
    restart? =
      case state.services[name].spec[:restart] || :always do
        :always -> true
        :on_failure -> status != {:exited, 0}
        :never -> false
      end

    if restart?, do: retry_later(state, name, :exited), else: set_status(state, name, :exited)
  end

  defp retry_later(state, name, status) do
    service = state.services[name]
    at = System.monotonic_time(:millisecond) + service.backoff
    service = %{service | retry_at: at, backoff: min(service.backoff * 2, @max_backoff), url: nil}
    set_status(put_in(state.services[name], service), name, status)
  end

  defp set_status(state, name, status) do
    if state.services[name].status != status do
      for pid <- Map.keys(state.subscribers), do: send(pid, {__MODULE__, name, status})
    end

    put_in(state.services[name].status, status)
  end
end
