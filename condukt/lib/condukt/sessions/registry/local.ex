defmodule Condukt.Sessions.Registry.Local do
  @moduledoc """
  The default session registry: Elixir's `Registry`, on the local node only.

  A session started on another node is not found by id here. Use
  `Condukt.Sessions.Registry.PG` or another adapter for a cluster.

  Options:

    * `:name` - the `Registry` name. Defaults to this module. Children are
      kept in a second one, under `:name` with `.Children` appended.
  """

  @behaviour Condukt.Sessions.Registry

  @impl true
  def child_spec(opts) do
    registries = [
      {Registry, keys: :unique, name: name(opts)},
      Supervisor.child_spec({Registry, keys: :duplicate, name: children_name(opts)}, id: :children)
    ]

    %{
      id: name(opts),
      type: :supervisor,
      start: {Supervisor, :start_link, [registries, [strategy: :one_for_one]]}
    }
  end

  @impl true
  def via(id, opts), do: {:via, Registry, {name(opts), id}}

  @impl true
  def whereis(id, opts) do
    case Registry.lookup(name(opts), id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @impl true
  def list(opts), do: Registry.select(name(opts), [{{:"$1", :_, :_}, [], [:"$1"]}])

  # Children are registered under their parent's id in a registry of
  # duplicate keys, which a process leaves as it exits.
  @impl true
  def join_parent(parent, opts) do
    {:ok, _owner} = Registry.register(children_name(opts), parent, nil)
    :ok
  end

  @impl true
  def children(parent, opts), do: opts |> children_name() |> Registry.lookup(parent) |> Enum.map(&elem(&1, 0))

  defp name(opts), do: Keyword.get(opts, :name, __MODULE__)
  defp children_name(opts), do: Module.concat(name(opts), Children)
end
