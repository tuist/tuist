defmodule Condukt.Sessions.Registry.Local do
  @moduledoc """
  The default session registry: Elixir's `Registry`, on the local node only.

  A session started on another node is not found by id here. Use
  `Condukt.Sessions.Registry.PG` or another adapter for a cluster.

  Options:

    * `:name` - the `Registry` name. Defaults to this module.
  """

  @behaviour Condukt.Sessions.Registry

  @impl true
  def child_spec(opts), do: Registry.child_spec(keys: :unique, name: name(opts))

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

  defp name(opts), do: Keyword.get(opts, :name, __MODULE__)
end
