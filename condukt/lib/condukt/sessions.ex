defmodule Condukt.Sessions do
  @moduledoc """
  Starts sessions under supervision and finds them again by id.

  Before this existed a session was a bare process held by whoever called
  `start_link/1`. That is workable for one caller running one agent, and it is
  the wrong shape for anything holding sessions on behalf of other people: with
  no registry there is no way to answer "is this session running?", reattach a
  reconnecting viewer, count what a tenant is using, or shut a set of them down
  in an orderly way.

  Sessions started here are registered under their own id, so the id a caller
  already has is the only handle it needs.

      {:ok, session} = Condukt.Sessions.start(MyApp.Agent, actor: user_id)
      id = Condukt.Session.id(session)

      Condukt.Sessions.whereis(id)
      Condukt.Sessions.alive?(id)
      Condukt.run(via(id), "hello")

  Sessions are `:temporary`: a conversation that has crashed should not be
  silently restarted underneath the person having it, because the process would
  come back without the turn it died in. Restarting is the caller's decision,
  and `Condukt.SessionStore` is how the messages survive to make it.
  """

  alias Condukt.SessionID

  @supervisor Condukt.Sessions.Supervisor
  @registry Condukt.Sessions.Registry

  @doc false
  def supervisor, do: @supervisor

  @doc false
  def registry, do: @registry

  @doc """
  Starts a supervised session and registers it under its id.

  Takes the same options as an agent's `start_link/1`. When no `:id` is given
  one is generated, which is also the name the session is registered under.
  """
  def start(agent_module, opts \\ []) do
    id = Keyword.get_lazy(opts, :id, &SessionID.generate/0)
    opts = opts |> Keyword.put(:id, id) |> Keyword.put(:name, via(id))

    DynamicSupervisor.start_child(@supervisor, %{
      id: {Condukt.Session, id},
      start: {agent_module, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    })
  end

  @doc """
  The `:via` tuple for a session id.

  Accepted anywhere a session is: `Condukt.run/3`, `Condukt.Session.stream/3`,
  and the rest of the session API.
  """
  def via(id), do: {:via, Registry, {@registry, id}}

  @doc "The session's pid, or `nil` when no session is running under that id."
  def whereis(id) do
    case Registry.lookup(@registry, id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @doc "Whether a session is running under this id."
  def alive?(id), do: whereis(id) != nil

  @doc """
  Every running session id.

  Ordering is the registry's and carries no meaning; sort by id for a
  time-ordered list, since `Condukt.SessionID` is time-ordered by construction.
  """
  def list do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc "How many sessions are running."
  def count, do: Registry.count(@registry)

  @doc """
  Stops a session.

  Returns `:ok` whether or not one was running, so a caller cleaning up does
  not have to race the session's own exit.
  """
  def stop(id) do
    case whereis(id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@supervisor, pid)
    end
  end

  @doc false
  def child_specs do
    [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
    ]
  end
end
