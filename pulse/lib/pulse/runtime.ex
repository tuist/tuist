defmodule Pulse.Runtime do
  @moduledoc """
  Owned, node-local dependency context. Production defaults use application
  configuration and the default service instance. Callers can instead provide
  an immutable context, including private instance names and configuration.

  Context is propagated explicitly at process/task startup; it is never looked
  up through other processes, and configuring it never changes application or
  OS environment. `with/2` restores the caller's context after an operation.
  """
  alias Pulse.Runtime.Server

  defstruct configs: %{}, instance: nil, env: %{}, shared: nil
  @key {__MODULE__, :current}

  def new(opts \\ []), do: struct!(__MODULE__, opts)
  def current, do: Process.get(@key)

  def share(runtime \\ current()) do
    table = :ets.new(__MODULE__, [:set, :public])
    :ets.insert(table, [{:configs, runtime.configs}, {:env, runtime.env}])
    shared = %{runtime | shared: table}
    install(shared)
    shared
  end

  defp values(%{shared: nil} = runtime, key), do: Map.fetch!(runtime, key)

  defp values(%{shared: table}, key) do
    case :ets.lookup(table, key) do
      [{^key, values}] -> values
      [] -> %{}
    end
  end

  defp update(runtime, key, fun) do
    value = fun.(values(runtime, key))
    if runtime.shared, do: :ets.insert(runtime.shared, {key, value}), else: install(Map.put(runtime, key, value))
    :ok
  end

  def install(runtime), do: Process.put(@key, runtime)

  def with(runtime, fun) do
    previous = current()
    install(runtime)

    try do
      fun.()
    after
      install(previous)
    end
  end

  def get_env(app, key, default \\ nil) do
    case current() do
      %__MODULE__{} = runtime -> Map.get(values(runtime, :configs), {app, key}, default)
      nil -> Application.get_env(app, key, default)
    end
  end

  def fetch_env!(app, key) do
    case get_env(app, key, :__missing__) do
      :__missing__ -> raise ArgumentError, "missing runtime configuration for #{inspect({app, key})}"
      value -> value
    end
  end

  def put_env(app, key, value) do
    runtime = current() || raise "configure an owned runtime before configuring dependencies"
    update(runtime, :configs, &Map.put(&1, {app, key}, value))
  end

  def delete_env(app, key) do
    runtime = current() || raise "configure an owned runtime before configuring dependencies"
    update(runtime, :configs, &Map.delete(&1, {app, key}))
  end

  def env(key, default \\ nil) do
    case current() do
      %__MODULE__{} = runtime -> Map.get(values(runtime, :env), key, default)
      nil -> System.get_env(key, default)
    end
  end

  def put_env(key, value) do
    runtime = current() || raise "configure an owned runtime before configuring secrets"
    update(runtime, :env, &Map.put(&1, key, value))
  end

  def delete_env(key) do
    runtime = current() || raise "configure an owned runtime before configuring secrets"
    update(runtime, :env, &Map.delete(&1, key))
  end

  # Instance identifiers are internal module atoms, never tenant/user input.
  # Test modules run their own cases sequentially and therefore reuse a finite
  # set of names; concurrent modules have distinct instances.
  def name(name) when is_atom(name) and not is_nil(name) do
    case current() do
      %__MODULE__{instance: instance} when is_atom(instance) and not is_nil(instance) ->
        if String.starts_with?(Atom.to_string(name), Atom.to_string(instance) <> "."),
          do: name,
          else: Module.concat(instance, name)

      _ ->
        name
    end
  end

  def name({:via, registry_module, {registry, key}}), do: {:via, registry_module, {name(registry), key}}
  def name(other), do: other
  def table(name), do: name(name)
  def call(server, request, timeout \\ 5000), do: GenServer.call(name(server), request, timeout)
  def cast(server, request), do: GenServer.cast(name(server), request)
  def stop(server, reason \\ :normal, timeout \\ :infinity), do: GenServer.stop(name(server), reason, timeout)
  def whereis(name), do: GenServer.whereis(name(name))

  def capture(fun) do
    runtime = current()
    fn -> __MODULE__.with(runtime, fun) end
  end

  def server_start(module, args, opts) do
    runtime = current()
    opts = Keyword.update(opts, :name, nil, &name/1) |> Keyword.reject(fn {k, v} -> k == :name and v == nil end)

    if runtime,
      do: GenServer.start_link(Server, {runtime, module, args}, opts),
      else: GenServer.start_link(module, args, opts)
  end

  def supervisor_start(module, args, opts) do
    runtime = current()
    opts = Keyword.update(opts, :name, nil, &name/1) |> Keyword.reject(fn {k, v} -> k == :name and v == nil end)

    if runtime,
      do: Supervisor.start_link(Pulse.Runtime.Supervisor, {runtime, module, args}, opts),
      else: Supervisor.start_link(module, args, opts)
  end

  def child_spec(child) do
    spec = Supervisor.child_spec(child, [])

    case current() do
      nil ->
        spec

      runtime ->
        spec
        |> Map.put_new(:modules, [elem(spec.start, 0)])
        |> Map.put(:start, {__MODULE__, :start_child, [runtime, spec.start]})
    end
  end

  def start_child(runtime, {module, function, args}) do
    __MODULE__.with(runtime, fn ->
      args =
        case {module, function, args} do
          {Registry, :start_link, [opts]} ->
            [Keyword.update!(opts, :name, &name/1)]

          {module, :start_link, [opts]} when module in [Task.Supervisor, DynamicSupervisor] ->
            [Keyword.update(opts, :name, nil, &name/1) |> Keyword.reject(fn {k, v} -> k == :name and v == nil end)]

          {:pg, :start_link, [scope]} ->
            [name(scope)]

          _ ->
            args
        end

      result = apply(module, function, args)
      # Task supervisor workers receive explicit captured closures, not ambient
      # inheritance. Binding the supervisor also scopes names for nested specs.
      result
    end)
  end
end
