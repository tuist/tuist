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

  ## Registries

  Where ids are registered is an adapter, a `Condukt.Sessions.Registry`. The
  default, `Condukt.Sessions.Registry.Local`, sees the local node only.
  `Condukt.Sessions.Registry.PG` and `Condukt.Sessions.Registry.Horde` see
  every node of a cluster, so `whereis/1`,
  `list/0`, `stop/1`, and the session API by id reach a session wherever it
  runs. Configure one before `:condukt` starts:

      config :condukt, session_registry: Condukt.Sessions.Registry.PG
  """

  alias Condukt.SessionID
  alias Condukt.Sessions.Registry.Local

  @supervisor Condukt.Sessions.Supervisor

  @doc false
  def supervisor, do: @supervisor

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
  def via(id) do
    {registry, opts} = registry()
    registry.via(id, opts)
  end

  @doc """
  The session's pid, or `nil` when the registry knows no session under that id.

  With a cluster-wide registry the pid may be on another node.
  """
  def whereis(id) do
    {registry, opts} = registry()
    registry.whereis(id, opts)
  end

  @doc "Whether a session is running under this id."
  def alive?(id), do: whereis(id) != nil

  @doc """
  Every running session id the registry sees.

  Ordering is the registry's and carries no meaning; sort by id for a
  time-ordered list, since `Condukt.SessionID` is time-ordered by construction.
  """
  def list do
    {registry, opts} = registry()
    registry.list(opts)
  end

  @doc "How many sessions are running."
  def count, do: length(list())

  @doc """
  Stops a session.

  Returns `:ok` whether or not one was running, so a caller cleaning up does
  not have to race the session's own exit. The running turn is aborted first,
  so tool calls parked in it run their `c:Condukt.Tool.cancel/2`.
  """
  def stop(id) do
    case whereis(id) do
      nil ->
        :ok

      pid ->
        abort(pid)
        # The supervisor on the session's own node, which may not be this one.
        DynamicSupervisor.terminate_child({@supervisor, node(pid)}, pid)
    end
  end

  defp abort(pid) do
    Condukt.Session.abort(pid)
  catch
    :exit, _reason -> :ok
  end

  @doc false
  def child_specs do
    {registry, opts} = registry()

    [
      registry.child_spec(opts),
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
    ]
  end

  defp registry do
    case Application.get_env(:condukt, :session_registry, Local) do
      {registry, opts} when is_atom(registry) and is_list(opts) -> {registry, opts}
      registry when is_atom(registry) -> {registry, []}
    end
  end
end
