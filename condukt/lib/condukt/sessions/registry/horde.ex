defmodule Condukt.Sessions.Registry.Horde do
  @moduledoc """
  A session registry on `Horde.Registry`, which sees sessions on every node
  in the Horde cluster.

      config :condukt, session_registry: Condukt.Sessions.Registry.Horde

  Options:

    * `:name` - the `Horde.Registry` name. Defaults to this module. Every node
      must use the same one.
    * `:members` - passed to `Horde.Registry`. Defaults to `:auto`, which
      joins the registries of every connected node as nodes come and go.

  Other options, such as `:delta_crdt_options`, are passed to
  `Horde.Registry` unchanged.

  Horde replicates names as a CRDT, so a session registered on another node a
  moment ago may not be found yet, and `list/1` may still include a session
  for a moment after it exits. When two nodes register the same id at once,
  Horde keeps one and stops the other session with a `{:name_conflict, ...}`
  exit. Session ids are generated `Condukt.SessionID`s unless a caller passes
  its own, so that only arises from callers reusing an id.

  Requires the optional `:horde` dependency.
  """

  @behaviour Condukt.Sessions.Registry

  # Horde is optional, so hosts that use another registry compile this
  # module without it.
  @compile {:no_warn_undefined, Horde.Registry}

  @impl true
  def child_spec(opts) do
    opts
    |> Keyword.put_new(:name, __MODULE__)
    |> Keyword.put_new(:members, :auto)
    |> Keyword.put(:keys, :unique)
    |> Horde.Registry.child_spec()
  end

  @impl true
  def via(id, opts), do: {:via, Horde.Registry, {name(opts), id}}

  @impl true
  def whereis(id, opts) do
    case Horde.Registry.lookup(name(opts), id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @impl true
  def list(opts), do: Horde.Registry.select(name(opts), [{{:"$1", :_, :_}, [{:is_binary, :"$1"}], [:"$1"]}])

  # A child is a key of its own, with its pid in it, so the process holds it
  # and it goes when the process does. Finding a parent's children scans the
  # registry, and a child that has just joined may take a moment to show,
  # as Horde's ids do.
  @impl true
  def join_parent(parent, opts) do
    {:ok, _owner} = Horde.Registry.register(name(opts), {:child, parent, self()}, nil)
    :ok
  end

  @impl true
  def children(parent, opts), do: Horde.Registry.select(name(opts), [{{{:child, parent, :"$1"}, :_, :_}, [], [:"$1"]}])

  defp name(opts), do: Keyword.get(opts, :name, __MODULE__)
end
