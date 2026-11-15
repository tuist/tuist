# Child Sessions

A coding agent often hands work to another agent and talks to it while it
works: it starts a sub-thread, sends it messages, and either waits for an
answer or carries on and hears the answer later. Condukt provides the
mechanism for that between sessions; the host decides the policy.

Condukt provides:

* **Parent links.** A session started with `parent: parent_id` is that
  session's child, and `Condukt.Sessions.children/1` lists a session's
  children on every connected node.
* **Input by id, at most once.** `Condukt.Sessions.submit/3` delivers a
  message to a session by id under a request id, so a retry never delivers
  twice, whether the session runs on this node, on another, or not at all.
* **Settled submissions.** When the turn an input started ends, its sender can
  be told: a tool call parked on `{Condukt.Sessions.Settled, key}` wakes with
  the answer, and an answer nobody waited for is submitted back to the sender
  as input.
* **Abort along the link.** `Condukt.Sessions.abort/2` aborts a session's turn
  and its children's, and `Condukt.Sessions.stop/2` can stop them together.

The host decides what a thread is (its rows, title, permissions, and UI),
whether a child gets its own sandbox and checkout, which tools the model sees,
and where stored input lives. A thread tool the model calls is host code built
on these functions; [a worked example](#a-thread-tool) follows below.

## Parents and children

Start a child with its parent's id:

```elixir
{:ok, _pid} = Condukt.Sessions.start(MyApp.Agent, id: child_id, parent: parent_id)

Condukt.Sessions.children(parent_id)
#=> [{child_id, #PID<...>}]
```

The link is recorded in a `:pg` scope that `:condukt` starts on every node:
the child's process joins a group named by its parent's id and leaves it when
it exits. `children/1` sees children on every connected node, whatever
registry is configured, and whether or not the parent itself runs. The link
lives as long as the child's process; a host that restarts a child passes
`:parent` again, from its own records.

Sub-agents started by the `subagent` and `background_subagent` tools record
their parent the same way.

## Submitting input

```elixir
:ok = Condukt.Sessions.submit(child_id, "Find where retries are configured", request_id: "call_42")
{:error, :duplicate} = Condukt.Sessions.submit(child_id, "Find where retries are configured", request_id: "call_42")
```

The session takes the input as a user message that waits behind its running
turn and any queued input, and starts a turn at once when it is idle. It shows
in the session's view as queued input of kind `:input`. Only the native
runtime takes queued input.

The request id names the submission. Use something the caller has again when
it retries, such as the id of the tool call making it. A second submission
with the same request id is answered `{:error, :duplicate}` and delivers
nothing; treat it as success.

The input **settles** when the turn it started ends:

| Outcome | When |
| --- | --- |
| `{:ok, answer}` | The turn finished with `answer`, its final text. |
| `{:error, reason}` | The turn failed. |
| `:aborted` | The turn was aborted, or an abort withdrew the input before it started. |

### Hearing the outcome

An input submitted with `from: sender_id` can tell the sender:

* `notify: key` delivers the outcome to the sender as a
  `Condukt.Sessions.Settled` signal under `key`. A tool call parked on
  `{Condukt.Sessions.Settled, key}` wakes with
  `%{session_id: id, request_id: request_id, outcome: outcome}`. A signal
  that arrives before the call parks is kept, as for any signal, so a fast
  answer is not lost. See [Waiting for Events](parking.md).
* `report: true` submits an outcome that no parked call took, other than
  `:aborted`, back to the sender as input, such as
  `[session 01J... answered] Retries are configured in lib/retry.ex`. That
  covers a sender that stopped waiting (its call timed out, or its turn was
  aborted) and one that is not running at all.

Use both: the model can wait for an answer, and still hears it when the wait
ends first. The report's own request id is derived from the input's, so it too
is delivered at most once.

## Where input goes

Without an inbox, `submit/3` reaches a running session through the configured
`Condukt.Sessions.Registry`, so with `Condukt.Sessions.Registry.PG` or
`Condukt.Sessions.Registry.Horde` the session may run on another node. A
session that is not running answers `{:error, :not_found}`, and the session
process remembers the request ids of its last 1,000 inputs.

That is not enough for a host whose sessions live longer than a process: one
that runs several replicas, restarts them, or stops idle sessions. Such a host
configures two things, each a behaviour it implements on its own
infrastructure:

* a `Condukt.Sessions.Inbox`, where input is stored, and
* a `Condukt.Sessions.Resumer`, which starts a session that input was stored
  for while no node ran it.

```elixir
config :condukt,
  inbox: {MyApp.SessionInbox, []},
  resumer: {MyApp.SessionResumer, []}
```

Every submission then goes through storage:

1. `c:Condukt.Sessions.Inbox.put/2` stores the input, once per
   `{session_id, request_id}`. This is where the input is accepted, so it is
   delivered at most once however often it is retried, from any node.
2. A running session is told to take its stored input with
   `c:Condukt.Sessions.Inbox.take/2`.
3. When no node runs the session, `c:Condukt.Sessions.Resumer.resume/2` starts
   it. A session with an inbox takes its stored input as it starts.

`Condukt.Sessions.start/2` takes `:inbox`, and `submit/3` takes `:inbox` and
`:resumer`, to override the configured ones. `Condukt.Sessions.Inbox.Memory`
keeps inputs in one node's memory, for tests and single-node hosts.

### Implementing an inbox

Condukt does not care what an inbox stores inputs in: a relational table, a
key-value store, a log, files on a shared volume. It relies on a contract:

* `put/2` stores an input unless one with the same `{session_id, request_id}`
  was ever put, taken or not, and returns `:ok` only once every node's
  `take/2` would see it. Otherwise it returns `{:error, :duplicate}`.
* `take/2` returns the session's untaken inputs in the order they were put
  and marks them taken in the same step, so two concurrent takers on any
  nodes never both get one.
* Inputs come back with every field as they were put. A
  `Condukt.Sessions.Input` is plain data: strings, a boolean, and a
  timestamp.

Most stores offer what this takes: an insert that fails on an existing key,
and an atomic claim of the rows or entries that are not yet claimed.
`Condukt.Sessions.Inbox.Conformance` checks the contract, including
concurrent takers, so run it against your inbox:

```elixir
defmodule MyApp.SessionInboxTest do
  use ExUnit.Case, async: true
  use Condukt.Sessions.Inbox.Conformance, inbox: {MyApp.SessionInbox, []}
end
```

`Condukt.Sessions.Inbox.Memory` is the reference implementation, and passes
the same suite.

### Implementing a resumer

How a session gets started somewhere is the host's scheduling policy, so it
lives apart from storage:

```elixir
defmodule MyApp.SessionResumer do
  @behaviour Condukt.Sessions.Resumer

  @impl true
  def resume(session_id, _opts) do
    # Hand the start to whatever runs the host's background work, keyed by the
    # session id so a second request while one is pending does nothing.
    MyApp.Jobs.enqueue_once({:resume_session, session_id})
  end
end

# The work it schedules:
def resume_session(session_id) do
  case Condukt.Sessions.drain(session_id) do
    :ok ->
      :ok

    {:error, :not_found} ->
      thread = MyApp.Threads.get!(session_id)
      {:ok, _pid} = Condukt.Sessions.start(MyApp.ThreadAgent, MyApp.Threads.session_opts(thread))
      :ok
  end
end
```

`resume/2` runs in the process that submitted the input, so it should return
quickly. It may be called while the session is starting, or runs on a node the
registry has not seen yet, so make it idempotent: work that finds the session
running calls `Condukt.Sessions.drain/1` instead of starting another. A
periodic sweep that resumes sessions with inputs left untaken for a while
covers a drain that reached a session as it exited.

### Delivery guarantees

* At most once, by request id: in the inbox for good, or in the session
  process for its last 1,000 inputs when there is no inbox.
* A session takes its inputs before they enter its queue, which lives in its
  process. A session that crashes between taking an input and finishing the
  turn it started loses that input, and its sender hears nothing. Senders
  that wait should park with a deadline.
* An abort, `Condukt.clear/1`, or stopping the session settles its running and
  queued inputs as `:aborted`. A crash settles nothing.
* Telling the sender is a signal or a submission from the target's node. It
  runs in its own process once the input settles, so it is lost if that node
  goes down at the same moment.

Each turn started from an input carries the input's request id as its
`:request_id`. That is the seam with a journaling `Condukt.SessionStore`: a
store that records turns by request id can resume a taken input's turn after a
crash instead of losing it.

## Aborting and stopping along the link

```elixir
# Aborts the parent's turn, then each child's, wherever they run.
:ok = Condukt.Sessions.abort(parent_id)

# Only the parent's.
:ok = Condukt.Sessions.abort(parent_id, children: false)

# Stops the parent and every descendant.
:ok = Condukt.Sessions.stop(parent_id, children: true)
```

An abort reaches descendants through the parent links, depth first, the
parent before its children so it starts no more work for them meanwhile.
Each aborted session keeps running and takes new input afterwards; its inputs
settle as `:aborted`. `Condukt.abort/1` on a session aborts that session only.

`Condukt.Sessions.stop/2` leaves children running by default: a child is a
session of its own, which a host may keep running after its parent's session
stops, for example because the parent's session only lives for one run.

## A thread tool

The model sees threads, not sessions. Here is a host tool that creates a
sub-thread or sends one a message, and either waits for the answer or lets it
arrive later as a message. Thread rows, titles, permissions, and the child's
own sandbox are the host's; the tool reaches the child only by id.

```elixir
defmodule MyApp.Tools.Thread do
  use Condukt.Tool

  alias Condukt.Sessions
  alias Condukt.Sessions.Settled

  @impl true
  def name, do: "thread"

  @impl true
  def description do
    """
    Works with sub-threads. create starts one on `message`; send gives an existing \
    thread another message. With wait: true the call returns the thread's answer; \
    otherwise the answer arrives later as a message.\
    """
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        action: %{type: "string", enum: ["create", "send"]},
        thread: %{type: "string", description: "send only. The thread id create returned."},
        title: %{type: "string", description: "create only. A short title."},
        message: %{type: "string"},
        wait: %{type: "boolean", description: "Wait for the thread's answer."}
      },
      required: ["action", "message"]
    }
  end

  @impl true
  def call(%{"action" => "create", "message" => message} = args, context) do
    # Host policy: the row, its title and owner, and a checkout of its own.
    # Keyed by the tool call, so a retried call finds the same thread.
    {:ok, thread} =
      MyApp.Threads.create_child(context.session_id,
        title: args["title"],
        idempotency_key: context.tool_call_id
      )

    submit(thread.id, message, args, context)
  end

  def call(%{"action" => "send", "thread" => id, "message" => message} = args, context) do
    with :ok <- MyApp.Threads.authorize_child(context.session_id, id) do
      submit(id, message, args, context)
    end
  end

  def call(_args, _context), do: {:error, "unknown action or missing arguments"}

  defp submit(thread_id, message, args, context) do
    wait? = args["wait"] == true
    key = "thread-" <> context.tool_call_id

    opts = [request_id: context.tool_call_id, from: context.session_id, report: true]
    opts = if wait?, do: Keyword.put(opts, :notify, key), else: opts

    case Sessions.submit(thread_id, message, opts) do
      result when result in [:ok, {:error, :duplicate}] and wait? ->
        {:park, %{thread: thread_id}, signals: [{Settled, key}], timeout: :timer.minutes(30)}

      result when result in [:ok, {:error, :duplicate}] ->
        {:ok, %{thread: thread_id, status: "working"}}

      {:error, reason} ->
        {:error, "could not reach thread #{thread_id}: #{inspect(reason)}"}
    end
  end

  @impl true
  def wake({:signal, {Settled, _key}, %{outcome: {:ok, answer}}}, %{thread: id}, _context),
    do: {:ok, %{thread: id, answer: answer}}

  def wake({:signal, {Settled, _key}, %{outcome: {:error, reason}}}, %{thread: id}, _context),
    do: {:error, "thread #{id} failed: #{inspect(reason)}"}

  def wake({:signal, {Settled, _key}, %{outcome: :aborted}}, %{thread: id}, _context),
    do: {:ok, %{thread: id, status: "stopped"}}

  # The answer still arrives as a message, through `report: true`.
  def wake(:timeout, %{thread: id}, _context),
    do: {:ok, %{thread: id, status: "working", note: "Its answer will arrive as a message."}}
end
```

The child session is started by the host's `Condukt.Sessions.Resumer`, with
`parent: parent_id` and whatever agent, sandbox, and tools the host gives
threads. What happens around a wait follows from the primitives:

* A child that answers before the call parks is not missed: the signal is
  kept until the call parks on its key.
* When the wait times out, the key closes, so the later answer reaches the
  parent through `report: true` as a message.
* Aborting the parent's turn ends the wait. With `Condukt.Sessions.abort/2`
  the child's turn is aborted too; with `Condukt.abort/1` it keeps working and
  reports its answer. To have a cancelled wait stop the child as well, add
  `cancel/2`:

  ```elixir
  @impl true
  def cancel(%{thread: id}, _context), do: Condukt.Sessions.abort(id)
  ```

* A parent whose session is not running when the answer comes is resumed by
  the report, through the inbox and the resumer, and starts a turn on it.

## Background sub-agents

The `background_subagent` tool (see [Sub-agents](subagents.md)) does much of
the same for agents that do not need a host:

| `background_subagent` | Primitive |
| --- | --- |
| `spawn` | Start a child with `parent:` and submit its task |
| `send` | `submit/3` (or steering, which `submit/3` does not do) |
| `wait` | Park on `{Condukt.Sessions.Settled, key}` |
| Answers posted back | `report: true` |
| `stop` | `Condukt.Sessions.abort(child_id, children: false)` |

They stay a separate, in-memory implementation rather than a special case of
these primitives, and their API is unchanged. A background sub-agent belongs to
its parent's process: it runs under the parent's supervisor, is found by
parent and name rather than by a registered id, shares the parent's sandbox
by default, appears in the parent's view, forwards its events to the parent's
notifier, and ends with the parent. A `wait` takes an answer whose report is
still queued back from the parent's queue, which needs both in one node's
memory. Built on stored input, each of those would cost a storage round trip
and gain nothing for an agent without a host. They do record their parent
link, so `Condukt.Sessions.children/1` lists them and
`Condukt.Sessions.abort/2` reaches them.

Use the primitives when children must outlive a process, run on other nodes,
or be the host's own objects, as threads are.
