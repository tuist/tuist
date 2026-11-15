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

  Sessions are `:temporary`: a conversation that has crashed is not silently
  restarted underneath the person having it. Restarting is the caller's
  decision. With a store that keeps a journal (see `Condukt.SessionStore`), the
  turn it died in survives too: start the session again under the same id and
  store, and `Condukt.Session.interrupted/1` reports the run, which
  `Condukt.Session.resume/2` continues where it stopped.

  ## Registries

  Where ids are registered is an adapter, a `Condukt.Sessions.Registry`. The
  default, `Condukt.Sessions.Registry.Local`, sees the local node only.
  `Condukt.Sessions.Registry.PG` and `Condukt.Sessions.Registry.Horde` see
  every node of a cluster, so `whereis/1`,
  `list/0`, `stop/1`, and the session API by id reach a session wherever it
  runs. Configure one before `:condukt` starts:

      config :condukt, session_registry: Condukt.Sessions.Registry.PG

  ## Child sessions and input by id

  A session started with `parent: parent_id` is that session's child.
  `children/1` lists a session's children on every connected node, and
  `abort/2` reaches them. `submit/3` delivers input to a session by id at
  most once, whether it runs on this node, another one, or nowhere yet, and
  tells the sender when the turn it started has settled. A host builds its
  own notion of a thread, with its own storage and tools, on these; see the
  [Child Sessions](child-sessions.md) guide.
  """

  alias Condukt.Session
  alias Condukt.SessionID
  alias Condukt.Sessions.Inbox
  alias Condukt.Sessions.Input
  alias Condukt.Sessions.Registry.Local
  alias Condukt.Sessions.Resumer
  alias Condukt.Sessions.Settled

  @supervisor Condukt.Sessions.Supervisor
  # The `:pg` scope that records parent links: each child joins the group
  # named by its parent's id, and leaves it when it exits.
  @tree Condukt.Sessions.Tree

  @doc false
  def supervisor, do: @supervisor

  @doc """
  Starts a supervised session and registers it under its id.

  Takes the same options as an agent's `start_link/1`. When no `:id` is given
  one is generated, which is also the name the session is registered under.
  Also takes:

    * `:parent` - the id of the session this one is a child of. The link is
      recorded while the child runs; a host that restarts a child passes it
      again.
    * `:inbox` - the `Condukt.Sessions.Inbox` the session takes stored input
      from. Defaults to the configured one.
  """
  def start(agent_module, opts \\ []) do
    id = Keyword.get_lazy(opts, :id, &SessionID.generate/0)

    opts =
      opts
      |> Keyword.put(:id, id)
      |> Keyword.put(:name, via(id))
      |> Keyword.put_new_lazy(:inbox, &Inbox.default/0)

    with :ok <- validate_parent(Keyword.get(opts, :parent), id) do
      DynamicSupervisor.start_child(@supervisor, %{
        id: {Condukt.Session, id},
        start: {agent_module, :start_link, [opts]},
        restart: :temporary,
        type: :worker
      })
    end
  end

  defp validate_parent(nil, _id), do: :ok
  defp validate_parent(id, id), do: {:error, {:invalid_parent, id}}
  defp validate_parent(parent, _id) when is_binary(parent) and parent != "", do: :ok
  defp validate_parent(parent, _id), do: {:error, {:invalid_parent, parent}}

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
  so tool calls parked in it run their `c:Condukt.Tool.cancel/2`, and the
  inputs it holds settle as `:aborted`.

  Options:

    * `:children` - also stop its children, and theirs, wherever they run.
      Defaults to `false`: a child is a session of its own, which a host may
      keep running after its parent's session stops.
    * `:drain` - hand the session off instead of ending its work, as a
      deploy does. The turn is not aborted, parked tool calls are not
      cancelled, and the sandbox processes they follow, such as a parked
      `Condukt.Tools.Bash` command, keep running for the node that starts
      the session again. The session there does not get the parked calls
      back yet: that needs a durable turn journal (see the Waiting for
      Events guide). Until then, those commands run until their own
      timeout with nothing reading or stopping them, and their process
      state stays in the sandbox. Defaults to `false`.
  """
  def stop(id, opts \\ []) do
    case whereis(id) do
      nil ->
        :ok

      pid ->
        if opts[:drain],
          do: hand_off(pid),
          else: stop_tree(id, pid, Keyword.get(opts, :children, false), MapSet.new([id]))
    end
  end

  defp hand_off(pid) do
    GenServer.stop(pid, {:shutdown, :drain})
  catch
    :exit, _reason -> :ok
  end

  defp stop_tree(id, pid, children?, seen) do
    abort_session(pid)
    if children?, do: each_child(id, seen, &stop_tree(&1, &2, true, &3))
    terminate(pid)
  end

  # The supervisor on the session's own node, which may not be this one. A
  # child started some other way, such as a background sub-agent, is stopped
  # directly.
  defp terminate(pid) do
    with {:error, :not_found} <- DynamicSupervisor.terminate_child({@supervisor, node(pid)}, pid) do
      GenServer.stop(pid, :shutdown)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  @doc """
  Aborts a session's running turn, as `Condukt.abort/1` does, and by default
  its children's.

  Returns `:ok`, or `{:error, :not_found}` when no session runs under `id`.

  Options:

    * `:children` - also abort the turns of its children, and theirs,
      wherever they run. Defaults to `true`. Each child keeps running and
      takes new input afterwards.
  """
  def abort(id, opts \\ []) do
    case whereis(id) do
      nil ->
        {:error, :not_found}

      pid ->
        abort_tree(id, pid, Keyword.get(opts, :children, true), MapSet.new([id]))
        :ok
    end
  end

  # The parent first, so it starts no more work for the children meanwhile.
  defp abort_tree(id, pid, children?, seen) do
    abort_session(pid)
    if children?, do: each_child(id, seen, &abort_tree(&1, &2, true, &3))
  end

  # `seen` holds the ids on the way down, so a link that loops ends there.
  defp each_child(id, seen, fun) do
    for {child_id, child_pid} <- children(id), not MapSet.member?(seen, child_id) do
      fun.(child_id, child_pid, MapSet.put(seen, child_id))
    end

    :ok
  end

  defp abort_session(pid) do
    Session.abort(pid)
  catch
    :exit, _reason -> :ok
  end

  @doc """
  The running children of the session `id`, as `{child_id, pid}` pairs sorted
  by id, on every node connected to this one.

  A child is listed from when it starts until it exits, whatever started it
  and whether or not `id` itself runs.
  """
  def children(id) when is_binary(id) do
    @tree
    |> :pg.get_members(id)
    |> Enum.uniq()
    |> Enum.flat_map(fn pid ->
      case session_id(pid) do
        nil -> []
        child_id -> [{child_id, pid}]
      end
    end)
    |> Enum.sort()
  end

  defp session_id(pid) do
    Session.id(pid)
  catch
    :exit, _reason -> nil
  end

  @doc false
  # Records `pid` as a child of the session `parent`, from the child's own
  # process, so the link goes when the child does.
  def join_parent(nil, _pid), do: :ok
  def join_parent(parent, pid) when is_binary(parent), do: :pg.join(@tree, parent, pid)

  @doc """
  Submits `text` to the session `id` as input, at most once per request id.

  The session takes the input as a user message that waits behind its running
  turn and any queued input, and starts a turn when the session is idle. The
  input **settles** when that turn ends, with `{:ok, answer}`,
  `{:error, reason}`, or `:aborted` when the turn is aborted or the input is
  withdrawn by an abort before it starts. Only the native runtime takes it.

  Options:

    * `:request_id` - required. A string that identifies this submission, such
      as the id of the tool call making it. A retry with the same one is
      answered `{:error, :duplicate}` and delivers nothing.
    * `:from` - the id of the session submitting, which `:notify` and
      `:report` answer.
    * `:notify` - a key. When the input settles, the session `:from` receives
      a `Condukt.Sessions.Settled` signal under it, which wakes a tool call
      parked on `{Condukt.Sessions.Settled, key}`.
    * `:report` - when `true`, an outcome other than `:aborted` that no call
      took through `:notify` is submitted to `:from` as input, so the sender
      hears the answer after it stopped waiting, or while it is not running.
    * `:inbox` - the `Condukt.Sessions.Inbox` to store the input in, or `nil`
      for none. Defaults to the configured one.
    * `:resumer` - the `Condukt.Sessions.Resumer` that starts the session when
      the input was stored and no node runs it, or a function of the session
      id. Defaults to the configured one.

  Without an inbox the input reaches only a running session, and a request id
  is remembered by the session process, for its last 1,000 inputs. With one,
  the input is stored first, wherever the session runs, and the inbox
  remembers request ids. A session that is not running is then started by the
  resumer, and takes the input as it starts.

  Returns `:ok` once the input is stored or queued, or `{:error, reason}`:

    * `:duplicate` - the request id was submitted before. Treat it as success.
    * `:not_found` - no inbox, and no session runs under `id`.
    * `{:invalid_option, key}`, or another validation error, for bad
      arguments.
  """
  def submit(id, text, opts \\ []) do
    {inbox, opts} = Keyword.pop_lazy(opts, :inbox, &Inbox.default/0)
    {resumer, opts} = Keyword.pop_lazy(opts, :resumer, &Resumer.default/0)

    with {:ok, input} <- Input.new(id, text, opts) do
      deliver(inbox, resumer, input)
    end
  end

  defp deliver(nil, _resumer, input) do
    with pid when is_pid(pid) <- whereis(input.session_id),
         result when result in [:ok, {:error, :duplicate}] <- Session.submit(pid, input) do
      result
    else
      _missing -> {:error, :not_found}
    end
  end

  defp deliver(inbox, resumer, input) do
    with :ok <- Inbox.put(inbox, input) do
      case drain(input.session_id) do
        :ok -> :ok
        {:error, :not_found} -> Resumer.resume(resumer, input.session_id)
      end
    end
  end

  @doc """
  Tells the running session `id` to take its stored input.

  `submit/3` does this itself. A host calls it when an input was stored while
  the session looked stopped but runs, for example from work its
  `Condukt.Sessions.Resumer` scheduled. Returns `:ok`, or
  `{:error, :not_found}` when no session runs under `id`.
  """
  def drain(id) do
    case whereis(id) do
      nil ->
        {:error, :not_found}

      pid ->
        send(pid, {__MODULE__, :drain})
        :ok
    end
  end

  @doc false
  # Runs in its own process once an input with a sender settles: delivers the
  # outcome to the parked call waiting on `:notify`, or reports it as input
  # through the target's own inbox and the configured resumer.
  def settle(%Input{} = input, outcome, inbox) do
    value = %{session_id: input.session_id, request_id: input.request_id, outcome: outcome}

    notified? =
      is_binary(input.notify) and
        Session.signal(input.from, Settled, input.notify, value) in [:ok, {:error, :duplicate}]

    if input.report and not notified? and outcome != :aborted do
      submit(input.from, report_text(input.session_id, outcome),
        request_id: "settled:" <> input.session_id <> ":" <> input.request_id,
        inbox: inbox
      )
    end

    :ok
  end

  defp report_text(id, {:ok, answer}), do: "[session #{id} answered] #{answer}"
  defp report_text(id, {:error, reason}), do: "[session #{id} failed: #{inspect(reason)}]"

  @doc false
  def child_specs do
    {registry, opts} = registry()

    [
      registry.child_spec(opts),
      %{id: @tree, start: {:pg, :start_link, [@tree]}},
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
