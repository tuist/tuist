defmodule Condukt.Sessions.Registry.PG do
  @moduledoc """
  A session registry on `:pg`, which sees sessions on every connected node.

  Each session joins a `:pg` group named by its id in its own scope, and
  leaves it when the process exits, so a host whose nodes are connected (for
  example with `libcluster`) finds a session by id from any of them.

      config :condukt, session_registry: Condukt.Sessions.Registry.PG

  Options:

    * `:scope` - the `:pg` scope, started by this adapter. Defaults to
      `Condukt.Sessions`. Every node of the cluster must use the same one.

  `:pg` is eventually consistent. A session started on another node a moment
  ago may not be found yet, and two nodes starting a session under the same id
  at the same moment can both succeed; whereis then prefers the local one. On
  one node, registrations of an id are serialised, and a session that just
  exited does not block a new one under its id.
  Session ids are generated `Condukt.SessionID`s unless a caller passes its own,
  so the second case only arises from callers reusing an id.
  """

  @behaviour Condukt.Sessions.Registry

  @default_scope Condukt.Sessions

  @impl Condukt.Sessions.Registry
  def child_spec(opts) do
    scope = scope(opts)
    %{id: {__MODULE__, scope}, start: {:pg, :start_link, [scope]}}
  end

  @impl Condukt.Sessions.Registry
  def via(id, opts), do: {:via, __MODULE__, {scope(opts), id}}

  @impl Condukt.Sessions.Registry
  def whereis(id, opts) do
    case whereis_name({scope(opts), id}) do
      :undefined -> nil
      pid -> pid
    end
  end

  @impl Condukt.Sessions.Registry
  def list(opts), do: :pg.which_groups(scope(opts))

  # The `:via` name contract. OTP calls `register_name/2` and
  # `unregister_name/1` from the process being started, so the pid joining or
  # leaving the group is always local. `:pg` drops a member that exited only
  # when its scope handles the exit, so local members that are no longer alive
  # are ignored rather than trusted.

  @doc false
  def register_name({scope, id}, pid) do
    # Serialises registrations of one id on this node; across nodes `:pg`
    # stays eventually consistent, as the moduledoc says.
    :global.trans({{__MODULE__, scope, id}, self()}, fn -> join_unless_taken(scope, id, pid) end, [node()])
  end

  defp join_unless_taken(scope, id, pid) do
    case live_members(scope, id) do
      [] ->
        :ok = :pg.join(scope, id, pid)
        :yes

      _members ->
        :no
    end
  end

  @doc false
  def unregister_name({scope, id}) do
    case Enum.filter(:pg.get_local_members(scope, id), &(&1 == self() or not Process.alive?(&1))) do
      [] -> :ok
      pids -> _ = :pg.leave(scope, id, pids)
    end

    :ok
  end

  @doc false
  def whereis_name({scope, id}) do
    case live_members(scope, id) do
      [pid | _rest] -> pid
      [] -> :undefined
    end
  end

  # Local members first, and only those still alive; remote members as `:pg`
  # reports them.
  defp live_members(scope, id) do
    local = Enum.filter(:pg.get_local_members(scope, id), &Process.alive?/1)
    local ++ Enum.reject(:pg.get_members(scope, id), &(node(&1) == node()))
  end

  @doc false
  def send({_scope, _id} = name, message) do
    case whereis_name(name) do
      :undefined ->
        :erlang.error(:badarg, [name, message])

      pid ->
        Kernel.send(pid, message)
        pid
    end
  end

  defp scope(opts), do: Keyword.get(opts, :scope, @default_scope)
end
